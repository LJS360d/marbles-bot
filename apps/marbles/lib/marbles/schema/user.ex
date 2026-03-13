defmodule Marbles.Schema.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :display_name, :string
    field :currency, :integer, default: 0
    field :role, Ecto.Enum, values: [:regular, :server_admin, :owner], default: :regular
    field :last_free_pull_at, :date

    has_many :identities, Marbles.Schema.UserIdentity
    has_many :collection, Marbles.Schema.UserMarble

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :currency, :role, :last_free_pull_at])
    |> validate_required([])
    |> validate_number(:currency, greater_than_or_equal_to: 0)
  end
end
