defmodule Marbles.Schema.RaceInstance do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types [:quick, :event]
  @statuses [:pending, :running, :finished, :cancelled]

  @type race_type :: :quick | :event
  @type status :: :pending | :running | :finished | :cancelled
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          race_type: race_type(),
          event_id: Ecto.UUID.t() | nil,
          pool_id: Ecto.UUID.t() | nil,
          track_slug: String.t() | nil,
          weather_key: String.t() | nil,
          seed: integer() | nil,
          status: status(),
          pot_coins: non_neg_integer(),
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          meta: map(),
          participants: Ecto.Association.NotLoaded.t() | [Marbles.Schema.RaceParticipant.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "race_instances" do
    field :race_type, Ecto.Enum, values: @types, default: :quick
    field :event_id, :binary_id
    field :pool_id, :binary_id
    field :track_slug, :string
    field :weather_key, :string
    field :seed, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :pot_coins, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :meta, :map, default: %{}

    has_many :participants, Marbles.Schema.RaceParticipant, foreign_key: :race_id

    timestamps()
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(race, attrs) do
    race
    |> cast(attrs, [
      :race_type,
      :event_id,
      :pool_id,
      :track_slug,
      :weather_key,
      :seed,
      :status,
      :pot_coins,
      :started_at,
      :finished_at,
      :meta
    ])
    |> validate_required([:race_type, :track_slug, :weather_key, :seed, :status])
  end
end
