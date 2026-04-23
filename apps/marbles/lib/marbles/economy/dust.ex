defmodule Marbles.Economy.Dust do
  @moduledoc false

  alias Marbles.Economy.{Upgrades, Effects}

  @spec amount_for_duplicate(pos_integer(), Ecto.UUID.t()) :: pos_integer()
  def amount_for_duplicate(rarity, user_id) when is_integer(rarity) do
    r = min(3, max(1, rarity))

    base =
      case r do
        1 -> 18
        2 -> 55
        _ -> 160
      end

    bonus = Upgrades.dust_gain_percent(user_id) + Effects.dust_gain_bonus_percent(user_id)
    max(1, trunc(base * (100 + bonus) / 100.0))
  end
end
