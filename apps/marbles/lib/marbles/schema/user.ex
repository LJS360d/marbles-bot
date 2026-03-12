defmodule Marbles.Schema.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :username, :string
    field :display_name, :string
    field :platform, :string, default: "discord"
    field :platform_id, :string
    field :currency, :integer, default: 0
    field :role, Ecto.Enum, values: [:regular, :server_admin, :owner], default: :regular
    field :last_free_pull_at, :date

    has_many :collection, Marbles.Schema.UserMarble

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name, :platform, :platform_id, :currency, :role, :last_free_pull_at])
    |> validate_required([:username, :platform, :platform_id])
    |> unique_constraint(:username)
    |> unique_constraint([:platform, :platform_id])
  end
end
