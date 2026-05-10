defmodule Marbles.Schema.RaceEventPool do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :running, :finished, :cancelled]

  @type status :: :pending | :running | :finished | :cancelled
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          event_id: Ecto.UUID.t() | nil,
          pool_index: non_neg_integer() | nil,
          status: status(),
          race_id: Ecto.UUID.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "race_event_pools" do
    field :pool_index, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :race_id, :binary_id

    belongs_to :event, Marbles.Schema.Event

    timestamps()
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(pool, attrs) do
    pool
    |> cast(attrs, [:event_id, :pool_index, :status, :race_id])
    |> validate_required([:event_id, :pool_index, :status])
    |> validate_number(:pool_index, greater_than_or_equal_to: 0)
    |> unique_constraint([:event_id, :pool_index])
  end
end
