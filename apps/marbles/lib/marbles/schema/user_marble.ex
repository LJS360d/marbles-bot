defmodule Marbles.Schema.UserMarble do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          level: integer(),
          experience: integer(),
          meta: map(),
          user_id: Ecto.UUID.t() | nil,
          marble_id: Ecto.UUID.t() | nil,
          user: Ecto.Association.NotLoaded.t() | map(),
          marble: Ecto.Association.NotLoaded.t() | map(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_marbles" do
    field :level, :integer, default: 1
    field :experience, :integer, default: 0

    # Metadata for addons, custom skins, or temporary buffs
    # e.g., %{"equipped_skin" => "gold_lustre", "bonus_speed" => 5}
    field :meta, :map, default: %{}

    belongs_to :user, Marbles.Schema.User
    belongs_to :marble, Marbles.Schema.Marble

    timestamps()
  end

  def changeset(user_marble, attrs) do
    user_marble
    |> cast(attrs, [:level, :experience, :meta, :user_id, :marble_id])
    |> validate_required([:user_id, :marble_id])
    |> unique_constraint([:user_id, :marble_id], name: :user_marbles_user_id_marble_id_index)
  end
end
