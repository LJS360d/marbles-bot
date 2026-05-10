defmodule Marbles.Schema.RaceReplay do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          race_id: Ecto.UUID.t() | nil,
          version: pos_integer(),
          payload: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "race_replays" do
    field :version, :integer, default: 1
    field :payload, :string
    field :inserted_at, :utc_datetime_usec

    belongs_to :race, Marbles.Schema.RaceInstance, define_field: false
    field :race_id, :binary_id
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(replay, attrs) do
    replay
    |> cast(attrs, [:race_id, :version, :payload, :inserted_at])
    |> validate_required([:race_id, :payload])
    |> unique_constraint(:race_id)
  end
end
