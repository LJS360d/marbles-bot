defmodule Marbles.Economy.SpawnRewards do
  @moduledoc false

  @spec roll_coins(float(), pos_integer(), float()) :: non_neg_integer()
  def roll_coins(spawn_rate, rarity, luck_bonus)
      when is_float(spawn_rate) and is_integer(rarity) and rarity >= 1 and is_float(luck_bonus) do
    spawn_rate = spawn_rate |> max(0.0) |> min(100.0)
    rarity = min(3, max(1, rarity))

    base_p =
      case rarity do
        3 -> 0.42
        2 -> 0.34
        _ -> 0.28
      end

    p = base_p - spawn_rate * 0.0045 + luck_bonus
    p = p |> max(0.02) |> min(0.88)

    roll = :rand.uniform(1_000_000) / 1_000_000.0

    if roll < p do
      low = 8 + rarity * 4
      high = 18 + rarity * 10
      span = max(1, high - low + 1)
      amount = low + :rand.uniform(span) - 1
      shrink = 1.0 - spawn_rate / 130.0
      shrink = shrink |> max(0.25) |> min(1.0)
      max(1, trunc(amount * shrink))
    else
      0
    end
  end
end
