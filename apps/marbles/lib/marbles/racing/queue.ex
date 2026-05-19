defmodule Marbles.Racing.Queue do
  @moduledoc ~S"""
  ELO-bracketed quick-race matchmaking queue (single-node).

  - Players are placed in a bracket = `div(elo, bracket_step)`.
  - Every `tick_ms` (1s default), the queue tries to assemble a race from
    one bracket plus its `near_brackets` neighbours.
  - If a player has waited longer than `max_wait_ms / 2`, the matcher
    widens the search; past `max_wait_ms`, it force-starts with the
    minimum party size.
  - Live counts are broadcast on the `"queue:public"` PubSub topic.
  - Per-user updates go to `"queue:user:#{user_id}"`.

  This module is intentionally a single GenServer; multi-node sharding is
  future work (see spec §11).
  """

  use GenServer
  require Logger

  alias Marbles.Repo
  alias Marbles.Racing.{Squads, Tracks, Weather}
  alias Marbles.Racing.Queue.BotFill
  alias Marbles.Racing.Engine.{Setup, Supervisor}
  alias Marbles.Schema.{RaceInstance, RaceParticipant, UserRaceStat}
  alias Marbles.Economy.Wallet
  alias Phoenix.PubSub, as: PS

  @public_topic "queue:public"

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec enqueue(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          :ok | {:error, atom()}
  def enqueue(user_id, squad_id, opts \\ []) do
    GenServer.call(__MODULE__, {:enqueue, user_id, squad_id, opts})
  end

  @spec leave(Ecto.UUID.t()) :: :ok
  def leave(user_id), do: GenServer.cast(__MODULE__, {:leave, user_id})

  @spec stats() :: map()
  def stats, do: GenServer.call(__MODULE__, :stats)

  @spec user_status(Ecto.UUID.t()) ::
          :idle
          | %{wage: non_neg_integer(), bracket: integer(), joined_at: integer()}
  def user_status(user_id), do: GenServer.call(__MODULE__, {:user_status, user_id})

  @spec public_topic() :: String.t()
  def public_topic, do: @public_topic

  @spec user_topic(Ecto.UUID.t()) :: String.t()
  def user_topic(user_id), do: "queue:user:#{user_id}"

  # --- Admin API (owner-only) ---

  @doc "Lists all currently queued entries with metadata. For admin view."
  @spec admin_list_entries() :: [map()]
  def admin_list_entries, do: GenServer.call(__MODULE__, :admin_list_entries)

  @doc """
  Removes a user from the queue and refunds their wage. Returns :ok or
  {:error, :not_queued}.
  """
  @spec admin_kick(Ecto.UUID.t()) :: :ok | {:error, :not_queued}
  def admin_kick(user_id), do: GenServer.call(__MODULE__, {:admin_kick, user_id})

  @doc """
  Forces match attempt on a bracket regardless of min_party / wait time.
  Returns :ok or {:error, :empty_bracket}.
  """
  @spec admin_force_start(integer()) :: :ok | {:error, :empty_bracket | :insufficient_setup}
  def admin_force_start(bracket), do: GenServer.call(__MODULE__, {:admin_force_start, bracket})

  @doc """
  Manually injects up to N bots into a bracket. Returns the number injected.
  """
  @spec admin_fill_bots(integer(), pos_integer()) :: {:ok, non_neg_integer()}
  def admin_fill_bots(bracket, count),
    do: GenServer.call(__MODULE__, {:admin_fill_bots, bracket, count})

  # --- GenServer ---

  defmodule Entry do
    @moduledoc false
    @enforce_keys [:user_id, :squad_id, :elo, :wage, :joined_at]
    defstruct [:user_id, :squad_id, :elo, :wage, :joined_at, bot: false]

    @type t :: %__MODULE__{
            user_id: Ecto.UUID.t(),
            squad_id: Ecto.UUID.t(),
            elo: integer(),
            wage: non_neg_integer(),
            joined_at: integer(),
            bot: boolean()
          }
  end

  @impl true
  def init(_opts) do
    cfg = config()
    bot_accounts = BotFill.load_accounts()
    bf = BotFill.config()

    cond do
      bf.enabled && bot_accounts == [] ->
        Logger.warning(
          "Quick queue bot fill is on but race_queue_bots has no rows (run seeds from apps/marbles, or link bot users in that table). Ecto logs [] only for bind params, not row count."
        )

      bf.enabled ->
        Logger.info("Quick queue bot fill: #{length(bot_accounts)} bot account(s) loaded.")

      true ->
        :ok
    end

    Process.send_after(self(), :tick, cfg.tick_ms)

    {:ok,
     %{
       brackets: %{},
       by_user: %{},
       recent_starts: [],
       config: cfg,
       bot_accounts: bot_accounts,
       bot_injected_at: %{}
     }}
  end

  defp schedule_bot_tick(%{enabled: true, interval_ms: ms}) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :bot_tick, ms)
  end

  defp schedule_bot_tick(_), do: :ok

  @impl true
  def handle_call({:enqueue, user_id, squad_id, opts}, _from, state) do
    if Map.has_key?(state.by_user, user_id) do
      {:reply, {:error, :already_queued}, state}
    else
      do_enqueue(user_id, squad_id, opts, state)
    end
  end

  def handle_call(:stats, _from, state), do: {:reply, build_stats(state), state}

  def handle_call({:user_status, user_id}, _from, state) do
    case Map.get(state.by_user, user_id) do
      nil ->
        {:reply, :idle, state}

      %{entry: entry, bracket: bracket} ->
        {:reply, %{wage: entry.wage, bracket: bracket, joined_at: entry.joined_at}, state}
    end
  end

  def handle_call(:admin_list_entries, _from, state) do
    now = System.monotonic_time(:millisecond)

    rows =
      Enum.flat_map(state.brackets, fn {bucket, entries} ->
        Enum.map(entries, fn %Entry{} = e ->
          %{
            user_id: e.user_id,
            squad_id: e.squad_id,
            elo: e.elo,
            wage: e.wage,
            bot: e.bot,
            bracket: bucket,
            waited_ms: now - e.joined_at
          }
        end)
      end)
      |> Enum.sort_by(&{&1.bracket, -&1.waited_ms})

    {:reply, rows, state}
  end

  def handle_call({:admin_kick, user_id}, _from, state) do
    case Map.get(state.by_user, user_id) do
      nil ->
        {:reply, {:error, :not_queued}, state}

      %{entry: %Entry{wage: wage, bot: bot}} ->
        if not bot, do: Wallet.credit(user_id, %{coins: wage})
        state = remove_user(state, user_id)
        PS.broadcast(Marbles.PubSub, user_topic(user_id), {:left, :admin_kick})
        broadcast_stats(state)
        {:reply, :ok, state}
    end
  end

  def handle_call({:admin_force_start, bucket}, _from, state) do
    case Map.get(state.brackets, bucket, []) do
      [] ->
        {:reply, {:error, :empty_bracket}, state}

      entries ->
        chosen = Enum.take(entries, state.config.max_party)

        if length(chosen) < state.config.min_party do
          state = form_race(chosen, state)
          {:reply, :ok, state}
        else
          state = form_race(chosen, state)
          {:reply, :ok, state}
        end
    end
  end

  def handle_call({:admin_fill_bots, bucket, count}, _from, state) do
    bot_accounts = BotFill.load_accounts()
    state = %{state | bot_accounts: bot_accounts}

    {state, injected} =
      Enum.reduce_while(1..count, {state, 0}, fn _, {st, n} ->
        case pick_free_bot(st.bot_accounts, st.by_user) do
          nil ->
            {:halt, {st, n}}

          acc ->
            entries = Map.get(st.brackets, bucket, [])
            wage = average_human_wage(entries, st.config.base_wage)
            elo = bucket * st.config.bracket_step + div(st.config.bracket_step, 2)

            entry = %Entry{
              user_id: acc.user_id,
              squad_id: acc.squad_id,
              elo: elo,
              wage: wage,
              joined_at: System.monotonic_time(:millisecond),
              bot: true
            }

            {:cont, {put_entry(st, entry, broadcast_user: false), n + 1}}
        end
      end)

    broadcast_stats(state)
    {:reply, {:ok, injected}, attempt_match(state)}
  end

  defp do_enqueue(user_id, squad_id, opts, state) do
    wage = Keyword.get(opts, :wage, state.config.base_wage)

    with :ok <- check_squad(user_id, squad_id),
         {:ok, elo} <- fetch_elo(user_id),
         :ok <- ensure_funds(user_id, wage) do
      entry = %Entry{
        user_id: user_id,
        squad_id: squad_id,
        elo: elo,
        wage: wage,
        joined_at: System.monotonic_time(:millisecond)
      }

      state = put_entry(state, entry, broadcast_user: true)
      broadcast_stats(state)

      # TODO dynamically figure out the bracket to use instead of hardcoding 10
      if Map.get(state.brackets, 10) |> length() == 1 do
        BotFill.config() |> schedule_bot_tick()
      end

      {:reply, :ok, attempt_match(state)}
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  @impl true
  def handle_cast({:leave, user_id}, state) do
    state = remove_user(state, user_id)
    broadcast_stats(state)
    PS.broadcast(Marbles.PubSub, user_topic(user_id), {:left, :user_request})
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.config.tick_ms)
    {:noreply, attempt_match(state)}
  end

  def handle_info(:bot_tick, state) do
    bot_accounts = BotFill.load_accounts()
    state = %{state | bot_accounts: bot_accounts}
    state = maybe_inject_bots(state)

    bf = BotFill.config()

    # TODO figure out the bracket to use instead of hardcoding 10
    if Map.get(state.brackets, 10) |> length() < bf.target_party do
      schedule_bot_tick(bf)
    end

    broadcast_stats(state)
    {:noreply, attempt_match(state)}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # --- Internals ---

  defp config do
    cfg = Application.get_env(:marbles, __MODULE__, [])

    %{
      bracket_step: Keyword.get(cfg, :bracket_step, 100),
      min_party: Keyword.get(cfg, :min_party, 4),
      max_party: Keyword.get(cfg, :max_party, 8),
      max_wait_ms: Keyword.get(cfg, :max_wait_ms, 30_000),
      near_brackets: Keyword.get(cfg, :near_brackets, 2),
      tick_ms: Keyword.get(cfg, :tick_ms, 1_000),
      base_wage: Keyword.get(cfg, :base_wage, 50)
    }
  end

  defp bracket_of(elo, state), do: div(elo, state.config.bracket_step)

  defp maybe_inject_bots(state) do
    cfg = BotFill.config()
    bot_accounts = Map.get(state, :bot_accounts, [])

    if cfg.enabled == false or bot_accounts == [] do
      state
    else
      now = System.monotonic_time(:millisecond)
      last_map = Map.get(state, :bot_injected_at, %{})

      state.brackets
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce({state, last_map}, fn bucket, {st, inj} ->
        cond do
          bucket > cfg.low_elo_max_bucket ->
            {st, inj}

          true ->
            entries = Map.get(st.brackets, bucket, [])
            n = length(entries)

            cond do
              n == 0 ->
                {st, inj}

              n >= cfg.target_party ->
                {st, inj}

              true ->
                case pick_free_bot(bot_accounts, st.by_user) do
                  nil ->
                    {st, inj}

                  acc ->
                    wage = average_human_wage(entries, st.config.base_wage)
                    elo = bucket * st.config.bracket_step + div(st.config.bracket_step, 2)

                    entry = %Entry{
                      user_id: acc.user_id,
                      squad_id: acc.squad_id,
                      elo: elo,
                      wage: wage,
                      joined_at: now,
                      bot: true
                    }

                    st = put_entry(st, entry, broadcast_user: false)
                    inj = Map.put(inj, bucket, now)
                    {st, inj}
                end
            end
        end
      end)
      |> then(fn {st, inj} -> %{st | bot_injected_at: inj} end)
    end
  end

  defp average_human_wage(entries, base) do
    humans = Enum.reject(entries, & &1.bot)

    case humans do
      [] ->
        base

      list ->
        trunc(Enum.sum(Enum.map(list, & &1.wage)) / length(list))
    end
    |> max(1)
  end

  defp pick_free_bot(accounts, by_user) do
    taken = Map.keys(by_user) |> MapSet.new()

    Enum.find_value(accounts, fn acc ->
      if MapSet.member?(taken, acc.user_id), do: nil, else: acc
    end)
  end

  defp put_entry(state, %Entry{} = entry, opts) do
    bucket = bracket_of(entry.elo, state)
    brackets = Map.update(state.brackets, bucket, [entry], &(&1 ++ [entry]))
    by_user = Map.put(state.by_user, entry.user_id, %{entry: entry, bracket: bucket})

    if Keyword.get(opts, :broadcast_user, true) and entry.bot != true do
      PS.broadcast(
        Marbles.PubSub,
        user_topic(entry.user_id),
        {:queued, %{bracket: bucket}}
      )
    end

    %{state | brackets: brackets, by_user: by_user}
  end

  defp remove_user(state, user_id) do
    case Map.pop(state.by_user, user_id) do
      {nil, _} ->
        state

      {%{bracket: bracket, entry: _entry}, by_user} ->
        brackets =
          Map.update!(state.brackets, bracket, fn list ->
            Enum.reject(list, &(&1.user_id == user_id))
          end)
          |> Enum.reject(fn {_b, list} -> list == [] end)
          |> Map.new()

        %{state | brackets: brackets, by_user: by_user}
    end
  end

  defp attempt_match(state) do
    state.brackets
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce(state, &maybe_form_match/2)
  end

  defp maybe_form_match(bucket, state) do
    if not Map.has_key?(state.brackets, bucket) do
      state
    else
      now = System.monotonic_time(:millisecond)
      window = window_for(now, state)

      candidates = entries_in_window(state, bucket, window)

      cond do
        length(candidates) >= state.config.max_party ->
          form_race(Enum.take(candidates, state.config.max_party), state)

        length(candidates) >= state.config.min_party ->
          form_race(candidates, state)

        true ->
          state
      end
    end
  end

  defp entries_in_window(state, bucket, window) do
    range = for d <- -window..window, do: bucket + d

    range
    |> Enum.flat_map(fn b -> Map.get(state.brackets, b, []) end)
    |> Enum.uniq_by(& &1.user_id)
    |> Enum.sort_by(& &1.joined_at)
    |> Enum.take(state.config.max_party)
  end

  defp window_for(now, state) do
    base = state.config.near_brackets

    max_age =
      state.brackets
      |> Enum.flat_map(fn {_b, list} -> Enum.map(list, & &1.joined_at) end)
      |> Enum.map(fn ja -> now - ja end)
      |> Enum.max(fn -> 0 end)

    cond do
      max_age > state.config.max_wait_ms -> base + 4
      max_age > div(state.config.max_wait_ms, 2) -> base + 2
      true -> base
    end
  end

  defp form_race(entries, state) do
    {paid, broke} = collect_wages(entries)

    state = notify_and_drop_broke(state, broke)

    cond do
      length(paid) < state.config.min_party ->
        refund_human_wages(paid)
        state

      true ->
        case build_setup(paid) do
          {:ok, setup} ->
            case Supervisor.start_race(setup) do
              {:ok, _pid} ->
                Logger.info("Quick race #{setup.race_id} started with #{length(paid)} players.")
                persist_pending_race(setup, paid)
                new_state = drop_users(state, Enum.map(paid, & &1.user_id))
                new_state = remember_recent_start(new_state, setup, paid)
                broadcast_matches(setup.race_id, paid)
                broadcast_stats(new_state)
                new_state

              {:error, reason} ->
                Logger.error("Failed to start race: #{inspect(reason)}")
                refund_human_wages(paid)
                state
            end

          {:error, reason} ->
            Logger.warning("Could not build race setup: #{inspect(reason)}")
            refund_human_wages(paid)
            state
        end
    end
  end

  defp refund_human_wages(paid) do
    Enum.each(paid, fn %Entry{} = e ->
      if not e.bot, do: Wallet.credit(e.user_id, %{coins: e.wage})
    end)
  end

  @spec collect_wages([Entry.t()]) :: {[Entry.t()], [Entry.t()]}
  defp collect_wages(entries) do
    Enum.reduce(entries, {[], []}, fn %Entry{} = e, {paid, broke} ->
      if e.bot do
        {[e | paid], broke}
      else
        case Wallet.debit(e.user_id, %{coins: e.wage}) do
          :ok -> {[e | paid], broke}
          {:error, _} -> {paid, [e | broke]}
        end
      end
    end)
    |> then(fn {paid, broke} -> {Enum.reverse(paid), Enum.reverse(broke)} end)
  end

  defp notify_and_drop_broke(state, []), do: state

  defp notify_and_drop_broke(state, broke) do
    Enum.each(broke, fn %Entry{user_id: uid} ->
      PS.broadcast(Marbles.PubSub, user_topic(uid), {:left, :insufficient_funds})
    end)

    state = drop_users(state, Enum.map(broke, & &1.user_id))
    broadcast_stats(state)
    state
  end

  defp build_setup(entries) do
    race_id = Ecto.UUID.generate()
    seed = :erlang.phash2({race_id, System.monotonic_time()})
    rng = :rand.seed_s(:exsss, {seed, 0, 0})

    case Tracks.pick_random(rng) do
      nil ->
        {:error, :no_tracks}

      {track, rng} ->
        {weather, _rng} = Weather.pick_random(rng, track.weather_bias)

        participants =
          Enum.map(entries, fn %Entry{} = e ->
            squad = Squads.get_user_squad(e.user_id, e.squad_id)

            case squad do
              {:ok, sq} ->
                digest = Squads.digest(sq)

                %{
                  user_id: e.user_id,
                  squad_id: sq.id,
                  racers: digest.racers,
                  coach: digest.coach,
                  elo: e.elo,
                  wage: e.wage
                }

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        if participants == [] do
          {:error, :no_participants}
        else
          {:ok,
           %Setup{
             race_id: race_id,
             race_type: :quick,
             seed: seed,
             track: track,
             weather: weather,
             participants: participants
           }}
        end
    end
  end

  defp persist_pending_race(%Setup{} = setup, entries) do
    Repo.transaction(fn ->
      pot = Enum.reduce(entries, 0, fn e, acc -> acc + e.wage end)

      {:ok, race} =
        %RaceInstance{}
        |> RaceInstance.changeset(%{
          id: setup.race_id,
          race_type: :quick,
          track_slug: setup.track.slug,
          weather_key: Atom.to_string(setup.weather.key),
          seed: setup.seed,
          status: :running,
          pot_coins: pot,
          started_at: DateTime.utc_now()
        })
        |> Repo.insert()

      Enum.each(entries, fn e ->
        %RaceParticipant{}
        |> RaceParticipant.changeset(%{
          race_id: race.id,
          user_id: e.user_id,
          squad_id: e.squad_id,
          wage_coins: e.wage,
          elo_before: e.elo
        })
        |> Repo.insert!()
      end)
    end)
  end

  defp drop_users(state, ids) do
    by_user = Map.drop(state.by_user, ids)

    brackets =
      state.brackets
      |> Enum.map(fn {b, list} ->
        {b, Enum.reject(list, fn entry -> entry.user_id in ids end)}
      end)
      |> Enum.reject(fn {_b, list} -> list == [] end)
      |> Map.new()

    %{state | brackets: brackets, by_user: by_user}
  end

  defp remember_recent_start(state, %Setup{} = setup, entries) do
    started = %{race_id: setup.race_id, count: length(entries), at: System.system_time(:second)}
    %{state | recent_starts: [started | Enum.take(state.recent_starts, 5)]}
  end

  defp broadcast_matches(race_id, entries) do
    Enum.each(entries, fn %Entry{} = e ->
      if not e.bot do
        PS.broadcast(Marbles.PubSub, user_topic(e.user_id), {:matched, race_id})
      end
    end)
  end

  defp broadcast_stats(state) do
    PS.broadcast(Marbles.PubSub, @public_topic, {:queue_stats, build_stats(state)})
  end

  defp build_stats(state) do
    %{
      total: state.by_user |> map_size(),
      brackets:
        state.brackets
        |> Enum.map(fn {b, list} -> {b, length(list)} end)
        |> Map.new(),
      bracket_step: state.config.bracket_step,
      recent_starts: state.recent_starts,
      max_party: state.config.max_party,
      min_party: state.config.min_party
    }
  end

  defp check_squad(user_id, squad_id) do
    case Squads.get_user_squad(user_id, squad_id) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :squad_not_owned}
    end
  end

  defp fetch_elo(user_id) do
    case Repo.get_by(UserRaceStat, user_id: user_id) do
      %UserRaceStat{elo: elo} -> {:ok, elo}
      nil -> {:ok, 1000}
    end
  end

  defp ensure_funds(user_id, wage) do
    case Wallet.ensure_affordable(user_id, %{coins: wage}) do
      :ok -> :ok
      {:error, :insufficient_coins} -> {:error, :insufficient_funds}
      err -> err
    end
  end
end
