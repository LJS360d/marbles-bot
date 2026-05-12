defmodule Marbles.Racing.Engine do
  @moduledoc ~S"""
  Server-authoritative race simulation.

  Each race is one `GenServer` started under
  `Marbles.Racing.Engine.Supervisor` and registered in
  `Marbles.Racing.Engine.Registry`. Ticks every `tick_ms` (default 33 ms,
  i.e. ~30 Hz). Frame diffs are broadcast over PubSub on
  `"race:#{race_id}"`.

  The simulation is 1D-along-the-track with stat-driven kinematics and
  ability modifiers. Three.js + cannon-es on the client handle visual
  smoothing. Determinism is provided by a seeded RNG so a given setup
  always replays the same way.
  """

  use GenServer
  require Logger

  alias Marbles.PubSub
  alias Marbles.Racing.{Abilities, Replay}
  alias Marbles.Racing.Engine.{Registry, Setup, State}
  alias Marbles.Racing.Abilities.TeamSignature
  alias Phoenix.PubSub, as: PS

  @default_tick_ms 33
  @default_send_every 3
  @default_hard_timeout_ms 240_000
  @coach_pulse_period 4.0
  @final_stretch_threshold 0.85

  @type subscription_topic :: String.t()

  @spec start_link(Setup.t()) :: GenServer.on_start()
  def start_link(%Setup{race_id: race_id} = setup) do
    GenServer.start_link(__MODULE__, setup, name: via(race_id))
  end

  @spec child_spec(Setup.t()) :: Supervisor.child_spec()
  def child_spec(%Setup{race_id: race_id} = setup) do
    %{
      id: {__MODULE__, race_id},
      start: {__MODULE__, :start_link, [setup]},
      restart: :transient,
      type: :worker
    }
  end

  @spec topic(Ecto.UUID.t()) :: String.t()
  def topic(race_id), do: "race:#{race_id}"

  @spec engine_running?(Ecto.UUID.t()) :: boolean()
  def engine_running?(race_id) do
    case lookup(race_id) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  @spec finish_now(Ecto.UUID.t()) :: :ok
  def finish_now(race_id) do
    case lookup(race_id) do
      {:ok, pid} -> GenServer.cast(pid, :finish_now)
      :error -> :ok
    end
  end

  @doc """
  Adds coins to the live pot of an in-progress race (in-race wagering).

  Returns `:ok` and broadcasts `{:pot_updated, %{pot_coins: ..., contributors: ...}}`
  on the race topic. Returns `{:error, :not_running}` if the race isn't live.
  """
  @spec add_wage(Ecto.UUID.t(), Ecto.UUID.t(), pos_integer()) ::
          :ok | {:error, :not_running | :invalid_amount}
  def add_wage(_race_id, _user_id, amount) when not (is_integer(amount) and amount > 0),
    do: {:error, :invalid_amount}

  def add_wage(race_id, user_id, amount) do
    case lookup(race_id) do
      {:ok, pid} -> GenServer.call(pid, {:add_wage, user_id, amount})
      :error -> {:error, :not_running}
    end
  end

  @doc "Returns a snapshot of the live pot and per-user contributions."
  @spec pot_snapshot(Ecto.UUID.t()) ::
          {:ok, %{pot_coins: non_neg_integer(), contributors: map()}}
          | {:error, :not_running}
  def pot_snapshot(race_id) do
    case lookup(race_id) do
      {:ok, pid} -> {:ok, GenServer.call(pid, :pot_snapshot)}
      :error -> {:error, :not_running}
    end
  end

  defp via(race_id), do: {:via, Elixir.Registry, {Registry, race_id}}

  defp lookup(race_id) do
    case Elixir.Registry.lookup(Registry, race_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(%Setup{} = setup) do
    Process.flag(:trap_exit, true)
    state = State.from_setup(setup, config())
    state = bootstrap(state)
    Process.send_after(self(), :tick, state.config.tick_ms)
    Process.send_after(self(), :hard_timeout, state.config.hard_timeout_ms)
    PS.broadcast(PubSub, topic(setup.race_id), {:setup, State.public_setup(state)})
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = tick(state)

    if state.finished_at do
      finalize(state)
      {:stop, :normal, state}
    else
      Process.send_after(self(), :tick, state.config.tick_ms)
      {:noreply, state}
    end
  end

  def handle_info(:hard_timeout, state) do
    Logger.warning("Race #{state.race_id} hit hard timeout; finalizing.")
    state = force_finish(state)
    finalize(state)
    {:stop, :normal, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_cast(:finish_now, state) do
    state = force_finish(state)
    finalize(state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_call({:add_wage, user_id, amount}, _from, state) do
    contribs = Map.update(state.live_contribs, user_id, amount, &(&1 + amount))
    state = %{state | pot_coins: state.pot_coins + amount, live_contribs: contribs}

    Phoenix.PubSub.broadcast(
      Marbles.PubSub,
      topic(state.race_id),
      {:pot_updated, %{pot_coins: state.pot_coins, contributors: contribs}}
    )

    {:reply, :ok, state}
  end

  def handle_call(:pot_snapshot, _from, state) do
    {:reply, %{pot_coins: state.pot_coins, contributors: state.live_contribs}, state}
  end

  # --- Engine internals ---

  defp config do
    Application.get_env(:marbles, __MODULE__, [])
    |> Map.new()
    |> Map.put_new(:tick_ms, @default_tick_ms)
    |> Map.put_new(:network_send_every, @default_send_every)
    |> Map.put_new(:hard_timeout_ms, @default_hard_timeout_ms)
  end

  defp bootstrap(%State{} = state) do
    state = apply_signature_and_coach(state, :race_start)
    state = apply_per_marble_triggers(state, :race_start)
    state
  end

  defp tick(%State{finished_at: nil} = state) do
    dt = state.config.tick_ms / 1000.0
    new_t = state.t + dt
    state = %{state | t: new_t, tick_index: state.tick_index + 1}

    state = maybe_emit_final_stretch(state)
    state = maybe_emit_coach_pulse(state)
    state = apply_per_marble_triggers(state, :tick)
    state = advance_kinematics(state, dt)
    state = compute_ranks(state)
    state = state |> append_replay_frame() |> maybe_broadcast_frame()

    if all_finished?(state) do
      %{state | finished_at: DateTime.utc_now()}
    else
      state
    end
  end

  defp tick(state), do: state

  defp force_finish(%State{} = state) do
    marbles =
      Enum.map(state.marbles, fn m ->
        if m.status == :finished,
          do: m,
          else: %{m | status: :finished, position: state.track.length_meters}
      end)

    %{state | marbles: marbles, finished_at: DateTime.utc_now()}
    |> compute_ranks()
  end

  defp maybe_emit_final_stretch(state) do
    threshold = state.track.length_meters * @final_stretch_threshold

    {marbles, triggered} =
      Enum.map_reduce(state.marbles, false, fn m, acc ->
        if not m.__final_stretched and m.position >= threshold do
          {%{m | __final_stretched: true}, acc or true}
        else
          {m, acc}
        end
      end)

    state = %{state | marbles: marbles}

    if triggered, do: apply_per_marble_triggers(state, :final_stretch), else: state
  end

  defp maybe_emit_coach_pulse(state) do
    if state.t - state.last_coach_pulse >= @coach_pulse_period do
      state = %{state | last_coach_pulse: state.t}
      apply_coach_triggers(state, :coach_pulse)
    else
      state
    end
  end

  defp apply_per_marble_triggers(state, trigger) do
    marbles =
      Enum.map(state.marbles, fn m ->
        squad = Map.fetch!(state.squads, m.user_id)
        ctx_base = %{trigger: trigger, role: :racer, race: race_view(state), meta: %{}}

        Abilities.resolve(trigger, :racer, m, squad)
        |> Enum.reduce(m, fn mod, acc ->
          mod.apply(Map.put(ctx_base, :marble, acc), acc)
        end)
      end)

    %{state | marbles: marbles}
  end

  defp apply_coach_triggers(state, trigger) do
    coaches_by_user = state.coaches

    Enum.reduce(coaches_by_user, state, fn {user_id, coach}, acc_state ->
      if is_nil(coach), do: acc_state, else: do_apply_coach(acc_state, user_id, coach, trigger)
    end)
  end

  defp do_apply_coach(state, user_id, coach, trigger) do
    squad = Map.fetch!(state.squads, user_id)
    ctx = %{trigger: trigger, role: :coach, marble: coach, race: race_view(state), meta: %{}}

    coach =
      Abilities.resolve(trigger, :coach, coach, squad)
      |> Enum.reduce(coach, fn mod, acc -> mod.apply(Map.put(ctx, :marble, acc), acc) end)

    {own_racers, others} = Enum.split_with(state.marbles, fn m -> m.user_id == user_id end)

    own_buffed =
      cond do
        coach[:__coach_buff_until_offset] not in [nil, 0.0] ->
          until = state.t + coach.__coach_buff_until_offset
          Enum.map(own_racers, fn m -> Map.put(m, :__coach_buff_until, until) end)

        coach[:__strategist_until] not in [nil, 0.0] ->
          Enum.map(own_racers, fn m ->
            Map.put(m, :__strategist_until, coach.__strategist_until)
          end)

        true ->
          own_racers
      end

    coach = Map.put(coach, :__coach_buff_until_offset, 0.0) |> Map.put(:__strategist_until, 0.0)

    %{
      state
      | marbles: own_buffed ++ others,
        coaches: Map.put(state.coaches, user_id, coach)
    }
  end

  defp advance_kinematics(state, dt) do
    weather_mods = state.weather.modifiers

    marbles =
      Enum.map(state.marbles, fn m ->
        if m.status == :finished do
          m
        else
          mods = Map.get(m, :modifiers, %{})

          accel_mult = Map.get(mods, :acceleration, 1.0) |> bound(0.5, 1.6)
          top_mult = Map.get(mods, :top_speed, 1.0) |> bound(0.5, 1.6)
          grip_offset = Map.get(mods, :grip_offset, 0.0)

          coach_top_bonus = if (m[:__coach_buff_until] || 0.0) > state.t, do: 1.03, else: 1.0
          coach_accel_bonus = if (m[:__strategist_until] || 0.0) > state.t, do: 1.05, else: 1.0

          base_top = 18.0 * m.base_stats.top_speed * top_mult * coach_top_bonus
          base_accel = 7.0 * m.base_stats.acceleration * accel_mult * coach_accel_bonus

          grip = bound(weather_mods.grip + grip_offset, 0.4, 1.0)
          top_speed = base_top * weather_mods.top_speed * grip
          accel = base_accel * grip

          stamina =
            max(0.0, m.stamina - dt * weather_mods.stamina_drain * (1.0 / m.base_stats.stamina))

          stamina_factor = if stamina < 0.2 * m.base_stats.stamina, do: 0.85, else: 1.0
          top_speed = top_speed * stamina_factor

          velocity = min(m.velocity + accel * dt, top_speed)
          position = min(state.track.length_meters, m.position + velocity * dt)

          status = if position >= state.track.length_meters, do: :finished, else: :running

          finished_at =
            if status == :finished and m.finished_at == nil, do: state.t, else: m.finished_at

          %{
            m
            | velocity: velocity,
              position: position,
              stamina: stamina,
              status: status,
              finished_at: finished_at,
              modifiers: %{}
          }
        end
      end)

    %{state | marbles: marbles}
  end

  defp compute_ranks(state) do
    sorted =
      state.marbles
      |> Enum.sort_by(fn m ->
        # finished marbles ordered by their finish time, ascending; running by position, descending
        case m.status do
          :finished -> {0, m.finished_at}
          _ -> {1, -m.position}
        end
      end)

    indexed = sorted |> Enum.with_index(1)
    rank_by_id = Map.new(indexed, fn {m, idx} -> {m.id, idx} end)

    marbles = Enum.map(state.marbles, fn m -> %{m | rank: Map.fetch!(rank_by_id, m.id)} end)
    %{state | marbles: marbles}
  end

  defp all_finished?(state), do: Enum.all?(state.marbles, &(&1.status == :finished))

  defp append_replay_frame(state) do
    frame = %{
      t: state.t,
      marbles:
        Enum.map(state.marbles, fn m ->
          %{
            id: m.id,
            user_id: m.user_id,
            x: m.x_anchor,
            y: m.y_anchor,
            z: m.position,
            vel: m.velocity,
            rank: m.rank,
            status: m.status
          }
        end)
    }

    %{state | replay_frames: [frame | state.replay_frames]}
  end

  defp maybe_broadcast_frame(state) do
    every = state.config.network_send_every
    pending = [hd(state.replay_frames) | state.pending_frames]

    if rem(state.tick_index, every) == 0 do
      PS.broadcast(PubSub, topic(state.race_id), {:frames, Enum.reverse(pending)})
      %{state | pending_frames: []}
    else
      %{state | pending_frames: pending}
    end
  end

  defp finalize(state) do
    summary = State.summary(state)
    # TODO: fix persistence of replays
    # Replay.persist(state)
    PS.broadcast(PubSub, topic(state.race_id), {:finished, summary})
    notify_parent(state, summary)
  end

  defp notify_parent(%State{parent_pid: nil}, _summary), do: :ok

  defp notify_parent(%State{parent_pid: pid, race_id: race_id}, summary) do
    send(pid, {:race_finished, race_id, summary})
    :ok
  end

  defp race_view(state) do
    %{
      t: state.t,
      tick: state.tick_index,
      track: %{length: state.track.length_meters},
      weather: state.weather,
      marbles: state.marbles
    }
  end

  defp apply_signature_and_coach(state, _trigger) do
    racers =
      Enum.map(state.marbles, fn m ->
        squad = Map.fetch!(state.squads, m.user_id)

        members =
          (squad.racers ++ [squad.coach])
          |> Enum.reject(&is_nil/1)

        squad_team_ids = Enum.map(members, & &1[:team_id])

        ctx = %{
          trigger: :race_start,
          role: :racer,
          marble: m,
          race: race_view(state),
          meta: %{squad_team_ids: squad_team_ids}
        }

        TeamSignature.apply(ctx, m)
      end)

    %{state | marbles: racers}
  end

  defp bound(v, lo, hi), do: v |> max(lo) |> min(hi)
end
