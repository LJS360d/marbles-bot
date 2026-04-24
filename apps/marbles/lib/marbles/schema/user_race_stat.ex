defmodule Marbles.Schema.UserRaceStat do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          elo: integer(),
          race_wins: integer(),
          race_losses: integer(),
          races_entered: integer(),
          total_currency_won: integer(),
          total_currency_wagered: integer(),
          highest_elo: integer(),
          current_streak: integer(),
          best_streak: integer(),
          user: Ecto.Association.NotLoaded.t() | Marbles.Schema.User.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_race_stats" do
    field :elo, :integer, default: 1000
    field :race_wins, :integer, default: 0
    field :race_losses, :integer, default: 0
    field :races_entered, :integer, default: 0
    field :total_currency_won, :integer, default: 0
    field :total_currency_wagered, :integer, default: 0
    field :highest_elo, :integer, default: 1000
    field :current_streak, :integer, default: 0
    field :best_streak, :integer, default: 0

    belongs_to :user, Marbles.Schema.User, type: :binary_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [
      :user_id,
      :elo,
      :race_wins,
      :race_losses,
      :races_entered,
      :total_currency_won,
      :total_currency_wagered,
      :highest_elo,
      :current_streak,
      :best_streak
    ])
    |> validate_required([:user_id])
    |> validate_number(:elo, greater_than_or_equal_to: 0)
    |> validate_number(:race_wins, greater_than_or_equal_to: 0)
    |> validate_number(:race_losses, greater_than_or_equal_to: 0)
    |> validate_number(:races_entered, greater_than_or_equal_to: 0)
    |> validate_number(:total_currency_won, greater_than_or_equal_to: 0)
    |> validate_number(:total_currency_wagered, greater_than_or_equal_to: 0)
    |> validate_number(:highest_elo, greater_than_or_equal_to: 0)
    |> validate_number(:current_streak, greater_than_or_equal_to: 0)
    |> validate_number(:best_streak, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_id)
  end
end
