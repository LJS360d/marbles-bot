defmodule Marbles.Schema.MarbleAsset do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "marble_assets" do
    field :type, Ecto.Enum, values: [:thumbnail, :splash, :action, :skin]
    field :filename, :string

    belongs_to :marble, Marbles.Schema.Marble
    timestamps()
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [:type, :filename, :marble_id])
    |> validate_required([:type, :filename])
  end
end
