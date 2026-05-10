defmodule Marbles.Racing.Events.Runner do
  @moduledoc """
  Drives the lifecycle of a single scheduled event: load registrations,
  divide into pools, run each pool race through `Marbles.Racing.Engine`,
  collect results, distribute payouts, persist replays.

  One transient `Task` is spawned per event run.
  """

  require Logger

  alias Marbles.Repo
  alias Marbles.Economy.Wallet
  alias Marbles.Racing.{Payouts, Squads, Tracks, Weather}
  alias Marbles.Racing.Engine.{Setup, Supervisor}
  alias Marbles.Schema.{Event, EventRegistration, InboxMessage, RaceEventPool, UserRaceStat}
  alias Phoenix.PubSub, as: PS

  @public_topic "events:public"

  @spec public_topic() :: String.t()
  def public_topic, do: @public_topic

  @spec start_event(Event.t()) :: :ok | {:error, atom()}
  def start_event(%Event{} = event) do
    case Task.Supervisor.start_child(Marbles.Racing.TaskSupervisor, fn -> run(event) end) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run(%Event{} = event) do
    Logger.info("Starting event run for #{event.id} (#{event.name})")
    PS.broadcast(Marbles.PubSub, @public_topic, {:event_started, event.id})

    registrations = list_registrations(event.id)
    cfg = event.config || %{}
    pool_size = Map.get(cfg, "pool_size", 8)
    pools = chunk_into_pools(registrations, pool_size)

    pool_results =
      pools
      |> Enum.with_index()
      |> Enum.map(fn {pool, idx} ->
        run_pool(event, pool, idx)
      end)
      |> Enum.reject(&is_nil/1)

    finalize(event, registrations, pool_results)
    PS.broadcast(Marbles.PubSub, @public_topic, {:event_finished, event.id})
    :ok
  end

  defp list_registrations(event_id) do
    import Ecto.Query

    from(r in EventRegistration,
      where: r.event_id == ^event_id and r.status == :registered,
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
  end

  defp chunk_into_pools(regs, size) when size > 0 do
    regs
    |> Enum.chunk_every(size, size, :discard)
    |> case do
      [] -> if regs == [], do: [], else: [regs]
      chunks -> chunks
    end
  end

  defp run_pool(event, regs, idx) do
    cfg = event.config || %{}
    seed = :erlang.phash2({event.id, idx, System.system_time()})
    rng = :rand.seed_s(:exsss, {seed, 0, 0})

    case pick_track(cfg, rng) do
      nil ->
        Logger.warning("No track available for event pool #{idx}")
        nil

      {track, rng} ->
        {weather, _rng} = pick_weather(cfg, track, rng)

        race_id = Ecto.UUID.generate()
        {:ok, _pool} = create_pool_row(event.id, idx, race_id)

        participants =
          Enum.map(regs, fn r ->
            squad_id = pick_user_squad_id(r.user_id)
            squad = squad_id && Squads.get_user_squad(r.user_id, squad_id)

            case squad do
              {:ok, sq} ->
                digest = Squads.digest(sq)

                %{
                  user_id: r.user_id,
                  squad_id: sq.id,
                  racers: digest.racers,
                  coach: digest.coach,
                  elo: fetch_elo(r.user_id),
                  wage: Map.get(cfg, "entry_fee_coins", 0)
                }

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        if participants == [] do
          nil
        else
          setup = %Setup{
            race_id: race_id,
            race_type: :event,
            event_id: event.id,
            seed: seed,
            track: track,
            weather: weather,
            participants: participants,
            parent_pid: self()
          }

          {:ok, _pid} = Supervisor.start_race(setup)

          receive do
            {:race_finished, ^race_id, summary} ->
              {idx, summary, participants}
          after
            240_000 -> nil
          end
        end
    end
  end

  defp pick_track(cfg, rng) do
    case Map.get(cfg, "track_pool", "any") do
      "any" -> Tracks.pick_random(rng)
      slugs when is_list(slugs) and slugs != [] -> Tracks.pick_random(rng, slugs)
      _ -> Tracks.pick_random(rng)
    end
  end

  defp pick_weather(cfg, track, rng) do
    case Map.get(cfg, "atmosphere", "auto") do
      "auto" ->
        bias =
          case Map.get(cfg, "weather_pool", "any") do
            "any" -> track.weather_bias
            keys when is_list(keys) -> Map.take(track.weather_bias, Enum.map(keys, &safe_atom/1))
            _ -> track.weather_bias
          end

        Weather.pick_random(rng, bias)

      key when is_binary(key) ->
        case Weather.get(key) do
          nil -> Weather.pick_random(rng, track.weather_bias)
          w -> {w, rng}
        end
    end
  end

  defp safe_atom(k) when is_atom(k), do: k

  defp safe_atom(k) when is_binary(k) do
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> nil
    end
  end

  defp create_pool_row(event_id, idx, _race_id) do
    %RaceEventPool{}
    |> RaceEventPool.changeset(%{
      event_id: event_id,
      pool_index: idx,
      status: :running
    })
    |> Repo.insert()
  end

  defp pick_user_squad_id(user_id) do
    import Ecto.Query
    alias Marbles.Schema.UserSquad

    from(s in UserSquad,
      where: s.user_id == ^user_id,
      order_by: [asc: s.slot_index],
      limit: 1,
      select: s.id
    )
    |> Repo.one()
  end

  defp fetch_elo(user_id) do
    case Repo.get_by(UserRaceStat, user_id: user_id) do
      %UserRaceStat{elo: elo} -> elo
      nil -> 1000
    end
  end

  defp finalize(event, registrations, pool_results) do
    cfg = event.config || %{}
    multiplier = Map.get(cfg, "payout_multiplier", 1.0)
    consolation = Map.get(cfg, "consolation_coins", 0)

    participants =
      Enum.map(registrations, fn r ->
        %{
          user_id: r.user_id,
          elo: fetch_elo(r.user_id),
          wage: Map.get(cfg, "entry_fee_coins", 0)
        }
      end)

    pool_results_norm =
      Enum.map(pool_results, fn {_idx, summary, parts} ->
        rank_to_user =
          parts
          |> Enum.map(& &1.user_id)
          |> Enum.zip(summary.finishers)
          |> Enum.map(fn {uid, %{rank: rank}} -> %{user_id: uid, position: rank} end)

        rank_to_user
      end)

    payouts =
      Payouts.compute_event(participants, pool_results_norm)
      |> Enum.map(fn p -> %{p | payout: round(p.payout * multiplier) + consolation} end)

    apply_payouts(event, payouts)
  end

  defp apply_payouts(event, payouts) do
    Enum.each(payouts, fn %{user_id: uid, position: pos, payout: coins, elo_after: elo_after} ->
      Wallet.credit(uid, %{coins: coins})
      update_elo(uid, elo_after)

      %InboxMessage{}
      |> InboxMessage.changeset(%{
        user_id: uid,
        title: "#{event.name} results",
        body: "Final position #{pos}. Payout: #{coins} coins.",
        type: "event_payout",
        data: %{event_id: event.id, position: pos, payout: coins}
      })
      |> Repo.insert()
    end)
  end

  defp update_elo(user_id, new_elo) do
    case Repo.get_by(UserRaceStat, user_id: user_id) do
      nil ->
        %UserRaceStat{}
        |> UserRaceStat.changeset(%{user_id: user_id, elo: new_elo, highest_elo: new_elo})
        |> Repo.insert()

      stat ->
        stat
        |> UserRaceStat.changeset(%{
          elo: new_elo,
          highest_elo: max(stat.highest_elo, new_elo)
        })
        |> Repo.update()
    end
  end
end
