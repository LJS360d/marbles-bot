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
          role: role(),
          last_marble_id: Ecto.UUID.t() | nil,
          identities: Ecto.Association.NotLoaded.t() | [map()],
          collection: Ecto.Association.NotLoaded.t() | [map()],
          race_stat: Ecto.Association.NotLoaded.t() | Marbles.Schema.UserRaceStat.t() | nil,
          last_marble: Ecto.Association.NotLoaded.t() | Marbles.Schema.Marble.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field :display_name, :string
    field :currency, :integer, virtual: true, default: 0
    field :dust, :integer, virtual: true, default: 0
    field :role, Ecto.Enum, values: [:regular, :server_admin, :owner], default: :regular

    belongs_to :last_marble, Marbles.Schema.Marble, type: :binary_id

    has_many :identities, Marbles.Schema.UserIdentity
    has_many :collection, Marbles.Schema.UserMarble
    has_one :race_stat, Marbles.Schema.UserRaceStat

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :display_name,
      :role,
      :last_marble_id
    ])
    |> validate_required([])
  end
end
