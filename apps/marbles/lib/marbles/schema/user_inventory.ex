defmodule Marbles.Schema.UserInventory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          item_type: String.t() | nil,
          item_id: String.t() | nil,
          quantity: integer(),
          meta: map(),
          user: Ecto.Association.NotLoaded.t() | Marbles.Schema.User.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_inventory" do
    field :item_type, :string
    field :item_id, :string
    field :quantity, :integer, default: 1
    field :meta, :map, default: %{}

    belongs_to :user, Marbles.Schema.User

    timestamps()
  end

  def changeset(inventory, attrs) do
    inventory
    |> cast(attrs, [:user_id, :item_type, :item_id, :quantity, :meta])
    |> validate_required([:user_id, :item_type, :item_id])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :item_type, :item_id],
      name: :user_inventory_user_id_item_type_item_id_index
    )
  end
end
