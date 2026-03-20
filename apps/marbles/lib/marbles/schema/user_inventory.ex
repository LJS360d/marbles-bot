defmodule Marbles.Schema.UserInventory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

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
