defmodule Marbles.Daily do
  @moduledoc """
  Handles daily reward claims and streak tracking.
  """

  alias Marbles.Repo
  alias Marbles.Schema.{UserDailyStreak, UserMarble}
  alias Marbles.Analytics
  alias Marbles.Economy.Mining
  alias Marbles.Economy.Experience
  alias Marbles.Economy.Effects
  alias Marbles.Accounts

  @base_coins 100
  @streak_multiplier 10
  @max_coins 500

  @doc """
  Claims the daily reward for the given user.

  Returns `{:ok, map}` on success with at least `coins`, `streak`, `items`, plus mining breakdown keys.
  Returns `{:error, reason}` if the user has already claimed today or on failure.
  """
  @spec claim_daily(Ecto.UUID.t()) :: {:ok, map()} | {:error, String.t()}
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

      streak_coins = streak_bonus_coins(new_streak)
      prev_claim_at = streak_record.last_claimed_at
      accrual_seconds = Mining.accrual_seconds(prev_claim_at, now, user_id)
      mining = Mining.compute_coins(user_id, accrual_seconds)
      total_coins = streak_coins + mining.coins
      mining_xp_breakdown = grant_mining_xp(user_id, mining.breakdown, mining.seconds)
      mining_xp_total = Enum.reduce(mining_xp_breakdown, 0, fn row, acc -> acc + row.xp end)

      user = Accounts.get_user!(user_id)
      {:ok, _} = Accounts.update_currency(user, total_coins)

      _updated_streak =
        streak_record
        |> UserDailyStreak.changeset(%{
          last_claimed_at: now,
          current_streak: new_streak,
          longest_streak: new_longest_streak
        })
        |> Repo.update!()

      items = give_random_items(user_id)

      _ =
        Analytics.record_event("daily_claim", nil, nil, user_id, %{
          "streak" => new_streak,
          "streak_coins" => streak_coins,
          "mining_coins" => mining.coins,
          "mining_seconds" => mining.seconds,
          "mining_roster_size" => mining.roster_size,
          "mining_xp_total" => mining_xp_total,
          "total_coins" => total_coins
        })

      _ =
        Analytics.record_event("mining_payout", nil, nil, user_id, %{
          "coins" => mining.coins,
          "seconds" => mining.seconds,
          "roster_size" => mining.roster_size,
          "xp_total" => mining_xp_total
        })

      %{
        coins: total_coins,
        streak_coins: streak_coins,
        mining_coins: mining.coins,
        mining_seconds: mining.seconds,
        mining_cap_seconds: mining.cap_seconds,
        mining_roster_size: mining.roster_size,
        mining_breakdown: mining.breakdown,
        mining_xp_total: mining_xp_total,
        mining_xp_breakdown: mining_xp_breakdown,
        streak: new_streak,
        items: items
      }
    end)
  end

  defp grant_mining_xp(user_id, breakdown, mining_seconds) do
    xp_bonus_pct = Effects.exp_gain_bonus_percent(user_id)
    hours = max(0.0, mining_seconds / 3600.0)

    breakdown
    |> Enum.reduce([], fn row, acc ->
      rarity = max(1, Map.get(row, :rarity, 1))
      level = max(1, Map.get(row, :level, 1))
      xp_rate_per_hour = 10.0 + level * 1.2 + rarity * 4.0
      base_xp = max(0, trunc(hours * xp_rate_per_hour))
      gained_xp = max(0, trunc(base_xp * (100 + xp_bonus_pct) / 100.0))
      user_marble_id = Map.get(row, :user_marble_id)

      cond do
        gained_xp <= 0 ->
          acc

        not is_binary(user_marble_id) ->
          acc

        true ->
          case Repo.get(UserMarble, user_marble_id) do
            %UserMarble{} = um ->
              updated =
                Experience.apply_xp_gain(um.level || 1, um.experience || 0, gained_xp, rarity)

              um
              |> UserMarble.changeset(%{
                level: updated.level,
                experience: updated.experience
              })
              |> Repo.update!()

              [
                %{
                  user_marble_id: user_marble_id,
                  name: Map.get(row, :name, "Marble"),
                  xp: gained_xp,
                  level: updated.level,
                  rarity: rarity,
                  gained_levels: updated.gained_levels
                }
                | acc
              ]

            nil ->
              acc
          end
      end
    end)
    |> Enum.reverse()
  end

  defp streak_bonus_coins(streak) do
    raw = @base_coins + streak * @streak_multiplier
    min(raw, @max_coins)
  end

  defp give_random_items(_user_id) do
    # TODO: Implement a proper item pool and random selection.
    # For now, we return an empty list.
    []
  end
end
