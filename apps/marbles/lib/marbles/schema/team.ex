defmodule Marbles.Schema.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "teams" do
    field :name, :string
    field :logo_url, :string
    field :color_hex, :string

    has_many :marbles, Marbles.Schema.Marble

    timestamps()
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :logo_url, :color_hex])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
