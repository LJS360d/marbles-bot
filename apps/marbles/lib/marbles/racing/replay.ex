defmodule Marbles.Racing.Replay do
  @moduledoc """
  Replay capture + persistence.

  The engine appends a snapshot frame each tick (in reverse order). On race
  end, this module serializes the buffer to JSON and persists it as a row in
  `race_replays`. Replays are deterministic given `seed + setup`.
  """

  alias Marbles.Repo
  alias Marbles.Racing.Engine.State, as: EngineState
  alias Marbles.Schema.RaceReplay

  @version 1

  @spec persist(EngineState.t()) :: {:ok, RaceReplay.t()} | {:error, term()}
  def persist(%EngineState{} = state) do
    payload = build_payload(state)
    json = Jason.encode!(payload)

    %RaceReplay{}
    |> RaceReplay.changeset(%{
      race_id: state.race_id,
      version: @version,
      payload: json,
      inserted_at: DateTime.utc_now()
    })
    |> Repo.insert(
      on_conflict: {:replace, [:payload, :version, :inserted_at]},
      conflict_target: :race_id
    )
  end

  @spec load(Ecto.UUID.t()) :: {:ok, map()} | {:error, :not_found}
  def load(race_id) do
    case Repo.get_by(RaceReplay, race_id: race_id) do
      nil ->
        {:error, :not_found}

      %RaceReplay{payload: json, version: v} ->
        case Jason.decode(json) do
          {:ok, payload} -> {:ok, Map.put(payload, "version", v)}
          {:error, _} -> {:error, :corrupted}
        end
    end
  end

  defp build_payload(state) do
    %{
      "version" => @version,
      "race_id" => state.race_id,
      "seed" => state.seed,
      "track" => %{
        "slug" => state.track.slug,
        "name" => state.track.name,
        "model_path" => state.track.model_path,
        "length_meters" => state.track.length_meters,
        "laps" => state.track.laps
      },
      "weather" => %{
        "key" => Atom.to_string(state.weather.key),
        "name" => state.weather.name,
        "modifiers" => state.weather.modifiers
      },
      "duration" => state.t,
      "frames" =>
        state.replay_frames
        |> Enum.reverse()
        |> Enum.map(&serialize_frame/1)
    }
  end

  defp serialize_frame(%{t: t, marbles: marbles}) do
    %{
      "t" => t,
      "marbles" =>
        Enum.map(marbles, fn m ->
          %{
            "id" => m.id,
            "user_id" => m.user_id,
            "x" => m.x,
            "y" => m.y,
            "z" => m.z,
            "vel" => m.vel,
            "rank" => m.rank,
            "status" => Atom.to_string(m.status)
          }
        end)
    }
  end
end
