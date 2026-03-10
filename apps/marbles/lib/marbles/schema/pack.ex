defmodule Marbles.Schema.Pack do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "packs" do
    field :name, :string
    field :description, :string
    field :cost, :integer
    field :active, :boolean, default: true

    # Many-to-many through a join table to define the pool
    many_to_many :marbles, Marbles.Schema.Marble, join_through: "pack_contents"

    timestamps()
  end

  def changeset(pack, attrs) do
    pack
    |> cast(attrs, [:name, :description, :cost, :active])
    |> validate_required([:name, :cost])
  end
end
