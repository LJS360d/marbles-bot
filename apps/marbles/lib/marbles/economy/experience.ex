defmodule Marbles.Economy.Experience do
  @moduledoc false

  @max_level 100

  @spec max_level() :: pos_integer()
  def max_level, do: @max_level

  @spec rarity_scale(pos_integer()) :: pos_integer()
  def rarity_scale(rarity) when is_integer(rarity) and rarity >= 1 do
    :math.pow(10, min(3, rarity) - 1)
    |> trunc()
    |> max(1)
  end

  @spec total_xp_for_level(pos_integer(), pos_integer()) :: non_neg_integer()
  def total_xp_for_level(level, rarity)
      when is_integer(level) and level >= 1 and is_integer(rarity) and rarity >= 1 do
    clamped_level = min(@max_level, level)
    base_total = clamped_level * clamped_level * clamped_level
    base_total * rarity_scale(rarity)
  end

  @spec level_from_total_xp(non_neg_integer(), pos_integer()) :: pos_integer()
  def level_from_total_xp(total_xp, rarity)
      when is_integer(total_xp) and total_xp >= 0 and is_integer(rarity) and rarity >= 1 do
    do_level_from_total_xp(total_xp, rarity, 1, @max_level)
  end

  @spec apply_xp_gain(integer(), integer(), integer(), pos_integer()) ::
          %{level: pos_integer(), experience: non_neg_integer(), gained_levels: non_neg_integer()}
  def apply_xp_gain(level, experience, gained_xp, rarity)
      when is_integer(level) and is_integer(experience) and is_integer(gained_xp) and
             is_integer(rarity) and rarity >= 1 do
    old_level = min(@max_level, max(1, level))
    old_xp = max(0, experience)
    delta_xp = max(0, gained_xp)
    new_total_xp = old_xp + delta_xp
    new_level = level_from_total_xp(new_total_xp, rarity)

    %{
      level: new_level,
      experience: new_total_xp,
      gained_levels: max(0, new_level - old_level)
    }
  end

  @spec do_level_from_total_xp(non_neg_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          pos_integer()
  defp do_level_from_total_xp(total_xp, rarity, low, high) do
    if low >= high do
      low
    else
      mid = div(low + high + 1, 2)

      if total_xp_for_level(mid, rarity) <= total_xp do
        do_level_from_total_xp(total_xp, rarity, mid, high)
      else
        do_level_from_total_xp(total_xp, rarity, low, mid - 1)
      end
    end
  end
end
