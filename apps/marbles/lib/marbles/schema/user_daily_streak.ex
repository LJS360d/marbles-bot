defmodule Marbles.Schema.UserDailyStreak do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_daily_streaks" do
    field :last_claimed_at, :utc_datetime_usec
    field :current_streak, :integer, default: 0
    field :longest_streak, :integer, default: 0

    belongs_to :user, Marbles.Schema.User

    timestamps()
  end

  def changeset(streak, attrs) do
    streak
    |> cast(attrs, [:user_id, :last_claimed_at, :current_streak, :longest_streak])
    |> validate_required([:user_id])
    |> validate_number(:current_streak, greater_than_or_equal_to: 0)
    |> validate_number(:longest_streak, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_id)
  end
end
