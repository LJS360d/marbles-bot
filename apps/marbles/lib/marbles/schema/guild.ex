defmodule Marbles.Schema.Guild do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "guilds" do
    field :name, :string
    has_many :channels, Marbles.Schema.Channel
    timestamps()
  end

  def changeset(guild, attrs) do
    guild
    |> cast(attrs, [:id, :name])
    |> validate_required([:id, :name])
  end
end
