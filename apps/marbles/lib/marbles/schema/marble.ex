defmodule Marbles.Schema.Marble do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "marbles" do
    field :name, :string
    field :edition, :string, default: "standard"
    field :role, Ecto.Enum, values: [:athlete, :coach, :support, :manager]
    field :rarity, :integer

    # Stats like %{"speed" => 50, "weight" => 70, "stamina" => 40}
    field :base_stats, :map, default: %{}

    belongs_to :team, Marbles.Schema.Team
    many_to_many :packs, Marbles.Schema.Pack, join_through: "pack_contents"
    has_many :user_marbles, Marbles.Schema.UserMarble
    has_many :assets, Marbles.Schema.MarbleAsset

    timestamps()
  end

  def changeset(marble, attrs) do
    marble
    |> cast(attrs, [:name, :edition, :role, :rarity, :base_stats, :team_id])
    |> validate_required([:name, :role, :rarity, :base_stats])
  end
end
