defmodule Marbles.Schema.UserSquad do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          slot_index: integer(),
          slots: Ecto.Association.NotLoaded.t() | [Marbles.Schema.UserSquadSlot.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_squads" do
    field :name, :string
    field :slot_index, :integer, default: 0

    belongs_to :user, Marbles.Schema.User
    has_many :slots, Marbles.Schema.UserSquadSlot, foreign_key: :squad_id

    timestamps()
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(squad, attrs) do
    squad
    |> cast(attrs, [:user_id, :name, :slot_index])
    |> validate_required([:user_id, :name, :slot_index])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_number(:slot_index, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :slot_index],
      name: :user_squads_user_id_slot_index_index
    )
  end
end
