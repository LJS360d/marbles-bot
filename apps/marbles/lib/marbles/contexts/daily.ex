defmodule Marbles.Daily do
  @moduledoc """
  Handles daily reward claims and streak tracking.
  """

  alias Marbles.Repo
  alias Marbles.Schema.{UserDailyStreak, User}

  @base_coins 100
  @streak_multiplier 10
  @max_coins 500

  @doc """
  Claims the daily reward for the given user.

  Returns `{:ok, %{coins: integer, streak: integer, items: list}}` on success.
  Returns `{:error, reason}` if the user has already claimed today or on failure.
  """
  def claim_daily(user_id) do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)

    Repo.transaction(fn ->
      # Get or create the streak record
      streak_record =
        case Repo.get_by(UserDailyStreak, user_id: user_id) do
          nil ->
            %UserDailyStreak{user_id: user_id, current_streak: 0, longest_streak: 0}
            |> Repo.insert!()

          record ->
            record
        end

      # Check if already claimed today
      if streak_record.last_claimed_at do
        last_claimed_date = DateTime.to_date(streak_record.last_claimed_at)

        if Date.compare(last_claimed_date, today) == :eq do
          Repo.rollback("You have already claimed your daily reward today.")
        end
      end

      # Calculate new streak
      new_streak =
        if streak_record.last_claimed_at do
          last_claimed_date = DateTime.to_date(streak_record.last_claimed_at)
          days_diff = Date.diff(today, last_claimed_date)

          cond do
            days_diff == 1 -> streak_record.current_streak + 1
            days_diff > 1 -> 1
            true -> streak_record.current_streak
          end
        else
          # First claim
          1
        end

      # Update longest streak if needed
      new_longest_streak = max(new_streak, streak_record.longest_streak)

      # Calculate coin reward
      coin_reward = calculate_coins(new_streak)

      # Update user's currency
      user = Repo.get!(User, user_id)
      {:ok, _} = Marbles.Accounts.update_currency(user, coin_reward)

      # Update streak record
      _updated_streak =
        streak_record
        |> UserDailyStreak.changeset(%{
          last_claimed_at: now,
          current_streak: new_streak,
          longest_streak: new_longest_streak
        })
        |> Repo.update!()

      # Give random items (for now, we'll just return an empty list)
      items = give_random_items(user_id)

      %{coins: coin_reward, streak: new_streak, items: items}
    end)
  end

  defp calculate_coins(streak) do
    raw = @base_coins + streak * @streak_multiplier
    min(raw, @max_coins)
  end

  defp give_random_items(_user_id) do
    # TODO: Implement a proper item pool and random selection.
    # For now, we return an empty list.
    []
  end
end
