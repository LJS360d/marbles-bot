defmodule Marbles.Racing do
  @moduledoc """
  Public façade for the racing subsystem.

  Re-exports a thin convenience surface; richer APIs live in the
  individual context modules under `Marbles.Racing.*`.
  """

  alias Marbles.Racing.{Abilities, Engine, Events, Queue, Squads, Tracks, Weather}
  alias Marbles.Repo
  alias Marbles.Schema.{RaceInstance, RaceParticipant}
  import Ecto.Query

  @spec list_abilities() :: [module()]
  defdelegate list_abilities(), to: Abilities, as: :all

  @spec list_tracks() :: [Tracks.descriptor()]
  defdelegate list_tracks(), to: Tracks, as: :all

  @spec list_weathers() :: [Weather.descriptor()]
  defdelegate list_weathers(), to: Weather, as: :all

  @spec list_user_squads(Ecto.UUID.t()) :: [Marbles.Schema.UserSquad.t()]
  defdelegate list_user_squads(user_id), to: Squads

  @spec enqueue_quick_race(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          :ok | {:error, atom()}
  defdelegate enqueue_quick_race(user_id, squad_id, opts \\ []), to: Queue, as: :enqueue

  @spec leave_queue(Ecto.UUID.t()) :: :ok
  defdelegate leave_queue(user_id), to: Queue, as: :leave

  @spec queue_stats() :: map()
  defdelegate queue_stats(), to: Queue, as: :stats

  @spec start_event!(Ecto.UUID.t()) :: :ok | {:error, atom()}
  defdelegate start_event!(event_id), to: Events, as: :start_now

  @spec engine_running?(Ecto.UUID.t()) :: boolean()
  defdelegate engine_running?(race_id), to: Engine

  @doc """
  Returns the race-id the user is currently participating in, if any. Looks
  up `race_participants` joined with `race_instances` for `status = :running`
  and a registered live engine.
  """
  @spec current_race_for(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def current_race_for(user_id) do
    candidate =
      from(p in RaceParticipant,
        join: r in RaceInstance,
        on: r.id == p.race_id,
        where: p.user_id == ^user_id and r.status == :running,
        order_by: [desc: r.started_at],
        limit: 1,
        select: r.id
      )
      |> Repo.one()

    if candidate && Engine.engine_running?(candidate), do: candidate, else: nil
  end
end
