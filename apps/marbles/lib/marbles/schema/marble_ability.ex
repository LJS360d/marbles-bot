defmodule Marbles.Schema.MarbleAbility do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          marble_id: Ecto.UUID.t() | nil,
          ability_key: String.t() | nil,
          marble: Ecto.Association.NotLoaded.t() | Marbles.Schema.Marble.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "marble_abilities" do
    field :ability_key, :string
    belongs_to :marble, Marbles.Schema.Marble
    timestamps()
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:marble_id, :ability_key])
    |> validate_required([:marble_id, :ability_key])
    |> validate_length(:ability_key, min: 1, max: 64)
    |> unique_constraint([:marble_id, :ability_key],
      name: :marble_abilities_marble_id_ability_key_index
    )
  end
end
