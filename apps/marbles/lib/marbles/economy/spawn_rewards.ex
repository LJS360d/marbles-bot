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

  @spec roll_claim_resources(float(), pos_integer(), float()) ::
          %{dust: non_neg_integer(), coins: non_neg_integer()}
  def roll_claim_resources(spawn_rate, rarity, luck_bonus)
      when is_float(spawn_rate) and is_integer(rarity) and rarity >= 1 and is_float(luck_bonus) do
    spawn_rate = spawn_rate |> max(0.0) |> min(100.0)
    rarity = min(3, max(1, rarity))
    scarcity = (100.0 - spawn_rate) / 100.0
    rarity_mult = 1.0 + (rarity - 1) * 0.15

    dust_p = 0.05 + scarcity * 0.75 + luck_bonus * 0.50
    dust_p = dust_p |> max(0.01) |> min(0.82)

    dust =
      if random_hit?(dust_p) do
        low = 1
        high = 2 + trunc(scarcity * 4.0)
        max(1, trunc(random_between(low, high) * rarity_mult))
      else
        0
      end

    coin_p = 0.005 + scarcity * 0.12 + luck_bonus * 0.20
    coin_p = coin_p |> max(0.002) |> min(0.35)

    coins =
      if random_hit?(coin_p) do
        low = 1
        high = 1 + trunc(scarcity * 5.0)
        max(1, trunc(random_between(low, high) * rarity_mult))
      else
        0
      end

    %{dust: dust, coins: coins}
  end

  @spec random_hit?(float()) :: boolean()
  defp random_hit?(probability) do
    :rand.uniform(1_000_000) / 1_000_000.0 < probability
  end

  @spec random_between(pos_integer(), pos_integer()) :: pos_integer()
  defp random_between(low, high) do
    span = max(1, high - low + 1)
    low + :rand.uniform(span) - 1
  end
end
