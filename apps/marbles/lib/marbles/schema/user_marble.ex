defmodule Marbles.Schema.UserMarble do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

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
  end
end
