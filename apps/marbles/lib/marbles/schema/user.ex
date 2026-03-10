defmodule Marbles.Schema.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    # Unique handle
    field :username, :string
    # Non-unique "pretty" name
    field :display_name, :string
    field :platform, :string, default: "discord"
    # The Snowflake/External ID
    field :platform_id, :string
    field :currency, :integer, default: 0

    has_many :collection, Marbles.Schema.UserMarble

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name, :platform, :platform_id, :currency])
    |> validate_required([:username, :platform, :platform_id])
    |> unique_constraint(:username)
    # Ensure a user can't have multiple accounts on the same platform
    |> unique_constraint([:platform, :platform_id])
  end
end
