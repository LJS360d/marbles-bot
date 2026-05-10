defmodule Marbles.Schema.UserSquadSlot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles [:racer_1, :racer_2, :racer_3, :coach]

  @type role :: :racer_1 | :racer_2 | :racer_3 | :coach
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          squad_id: Ecto.UUID.t() | nil,
          role: role() | nil,
          user_marble_id: Ecto.UUID.t() | nil,
          squad: Ecto.Association.NotLoaded.t() | Marbles.Schema.UserSquad.t() | nil,
          user_marble: Ecto.Association.NotLoaded.t() | Marbles.Schema.UserMarble.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_squad_slots" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :squad, Marbles.Schema.UserSquad
    belongs_to :user_marble, Marbles.Schema.UserMarble

    timestamps()
  end

  @spec roles() :: [role()]
  def roles, do: @roles

  @spec racer_roles() :: [role()]
  def racer_roles, do: [:racer_1, :racer_2, :racer_3]

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:squad_id, :role, :user_marble_id])
    |> validate_required([:squad_id, :role, :user_marble_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:squad_id, :role],
      name: :user_squad_slots_squad_id_role_index
    )
  end
end
