defmodule Marbles.Schema.Pack do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "packs" do
    field :name, :string
    field :description, :string
    field :cost, :integer
    field :active, :boolean, default: true
    field :start_date, :date
    field :end_date, :date
    field :banner_path, :string

    many_to_many :marbles, Marbles.Schema.Marble, join_through: "pack_contents"

    timestamps()
  end

  def changeset(pack, attrs) do
    pack
    |> cast(attrs, [:name, :description, :cost, :active, :start_date, :end_date, :banner_path])
    |> validate_required([:name, :cost])
  end
end
