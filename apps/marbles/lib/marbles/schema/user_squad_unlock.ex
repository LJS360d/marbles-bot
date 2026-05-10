defmodule Marbles.Schema.UserSquadUnlock do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          max_slots: pos_integer(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_squad_unlocks" do
    field :max_slots, :integer, default: 1
    belongs_to :user, Marbles.Schema.User
    timestamps()
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(unlock, attrs) do
    unlock
    |> cast(attrs, [:user_id, :max_slots])
    |> validate_required([:user_id, :max_slots])
    |> validate_number(:max_slots, greater_than: 0, less_than_or_equal_to: 16)
    |> unique_constraint(:user_id)
  end
end
