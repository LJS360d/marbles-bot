defmodule Marbles.Schema.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type role :: :regular | :server_admin | :owner
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          display_name: String.t() | nil,
          currency: integer(),
          dust: integer(),
          mine_roster: map(),
          role: role(),
          identities: Ecto.Association.NotLoaded.t() | [map()],
          collection: Ecto.Association.NotLoaded.t() | [map()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field :display_name, :string
    field :currency, :integer, default: 0
    field :dust, :integer, default: 0
    field :mine_roster, :map, default: %{}
    field :role, Ecto.Enum, values: [:regular, :server_admin, :owner], default: :regular
    has_many :identities, Marbles.Schema.UserIdentity
    has_many :collection, Marbles.Schema.UserMarble

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :currency, :dust, :mine_roster, :role])
    |> validate_required([])
    |> validate_number(:currency, greater_than_or_equal_to: 0)
    |> validate_number(:dust, greater_than_or_equal_to: 0)
  end
end
