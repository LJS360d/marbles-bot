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
          elo: integer(),
          race_wins: integer(),
          race_losses: integer(),
          races_entered: integer(),
          total_currency_won: integer(),
          total_currency_wagered: integer(),
          highest_elo: integer(),
          current_streak: integer(),
          best_streak: integer(),
          last_marble_id: Ecto.UUID.t() | nil,
          identities: Ecto.Association.NotLoaded.t() | [map()],
          collection: Ecto.Association.NotLoaded.t() | [map()],
          last_marble: Ecto.Association.NotLoaded.t() | Marbles.Schema.Marble.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field :display_name, :string
    field :currency, :integer, default: 0
    field :dust, :integer, default: 0
    field :mine_roster, :map, default: %{}
    field :role, Ecto.Enum, values: [:regular, :server_admin, :owner], default: :regular
    field :elo, :integer, default: 1000
    field :race_wins, :integer, default: 0
    field :race_losses, :integer, default: 0
    field :races_entered, :integer, default: 0
    field :total_currency_won, :integer, default: 0
    field :total_currency_wagered, :integer, default: 0
    field :highest_elo, :integer, default: 1000
    field :current_streak, :integer, default: 0
    field :best_streak, :integer, default: 0

    belongs_to :last_marble, Marbles.Schema.Marble, type: :binary_id

    has_many :identities, Marbles.Schema.UserIdentity
    has_many :collection, Marbles.Schema.UserMarble

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :display_name,
      :currency,
      :dust,
      :mine_roster,
      :role,
      :elo,
      :race_wins,
      :race_losses,
      :races_entered,
      :total_currency_won,
      :total_currency_wagered,
      :highest_elo,
      :current_streak,
      :best_streak,
      :last_marble_id
    ])
    |> validate_required([])
    |> validate_number(:currency, greater_than_or_equal_to: 0)
    |> validate_number(:dust, greater_than_or_equal_to: 0)
    |> validate_number(:elo, greater_than_or_equal_to: 0)
    |> validate_number(:race_wins, greater_than_or_equal_to: 0)
    |> validate_number(:race_losses, greater_than_or_equal_to: 0)
    |> validate_number(:races_entered, greater_than_or_equal_to: 0)
    |> validate_number(:total_currency_won, greater_than_or_equal_to: 0)
    |> validate_number(:total_currency_wagered, greater_than_or_equal_to: 0)
    |> validate_number(:highest_elo, greater_than_or_equal_to: 0)
    |> validate_number(:current_streak, greater_than_or_equal_to: 0)
    |> validate_number(:best_streak, greater_than_or_equal_to: 0)
  end
end
