defmodule Marbles.Racing.Engine.Setup do
  @moduledoc "Input contract for `Marbles.Racing.Engine.start_link/1`."

  @type participant :: %{
          required(:user_id) => Ecto.UUID.t(),
          required(:squad_id) => Ecto.UUID.t() | nil,
          required(:racers) => [map()],
          required(:coach) => map() | nil,
          required(:elo) => integer(),
          required(:wage) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          race_id: Ecto.UUID.t(),
          race_type: :quick | :event,
          event_id: Ecto.UUID.t() | nil,
          pool_id: Ecto.UUID.t() | nil,
          seed: integer(),
          track: map(),
          weather: map(),
          participants: [participant()],
          parent_pid: pid() | nil
        }

  defstruct [
    :race_id,
    :seed,
    :track,
    :weather,
    :race_type,
    :event_id,
    :pool_id,
    :parent_pid,
    participants: []
  ]
end
