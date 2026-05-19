defmodule Marbles.Schema.MarbleUpgrade do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_marble_id: Ecto.UUID.t() | nil,
          upgrade_type: String.t() | nil,
          meta: map(),
          user_marble: Ecto.Association.NotLoaded.t() | map(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "marble_upgrades" do
    field :upgrade_type, :string
    field :meta, :map, default: %{}

    belongs_to :user_marble, Marbles.Schema.UserMarble

    timestamps()
  end

  def changeset(upgrade, attrs) do
    upgrade
    |> cast(attrs, [:user_marble_id, :upgrade_type, :meta])
    |> validate_required([:user_marble_id, :upgrade_type])
  end
end
