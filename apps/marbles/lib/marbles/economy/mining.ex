defmodule Marbles.Economy.Mining do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.{User, UserMarble, Marble}
  alias Marbles.Economy.{Upgrades, Effects}

  @base_offline_hours 36

  @spec max_accrual_seconds(Ecto.UUID.t()) :: pos_integer()
  def max_accrual_seconds(user_id) do
    extra_h = Upgrades.mine_extra_offline_hours(user_id) + Effects.mine_offline_cap_bonus_hours(user_id)
    hours = @base_offline_hours + extra_h
    hours * 3600
  end

  @spec accrual_seconds(DateTime.t() | nil, DateTime.t(), Ecto.UUID.t()) :: non_neg_integer()
  def accrual_seconds(last_claimed_at, now, user_id) do
    if is_nil(last_claimed_at) do
      0
    else
      raw = DateTime.diff(now, last_claimed_at, :second) |> max(0)
      min(raw, max_accrual_seconds(user_id))
    end
  end

  @spec compute_coins(Ecto.UUID.t(), non_neg_integer()) :: %{
          coins: non_neg_integer(),
          seconds: non_neg_integer(),
          cap_seconds: pos_integer(),
          roster_size: non_neg_integer()
        }
  def compute_coins(user_id, accrual_seconds) when is_integer(accrual_seconds) and accrual_seconds >= 0 do
    user = Repo.get!(User, user_id)
    roster_ids = roster_slot_ids(user.mine_roster)
    cap = max_accrual_seconds(user_id)

    if roster_ids == [] or accrual_seconds == 0 do
      %{coins: 0, seconds: accrual_seconds, cap_seconds: cap, roster_size: 0}
    else
      roster = load_roster(user_id, roster_ids)

      if roster == [] do
        %{coins: 0, seconds: accrual_seconds, cap_seconds: cap, roster_size: 0}
      else
        hours = accrual_seconds / 3600.0
        per_hour = roster |> Enum.map(&marble_hour_rate/1) |> Enum.sum()
        yield_mult = (100 + Upgrades.mine_yield_percent(user_id) + Effects.mine_yield_bonus_percent(user_id)) / 100.0
        coins = trunc(hours * per_hour * yield_mult) |> max(0)
        %{coins: coins, seconds: accrual_seconds, cap_seconds: cap, roster_size: length(roster)}
      end
    end
  end

  defp roster_slot_ids(nil), do: []

  defp roster_slot_ids(map) when is_map(map) do
    ids = Map.get(map, "slots") || Map.get(map, :slots) || []
    ids |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.take(5)
  end

  defp load_roster(user_id, ids) do
    from(um in UserMarble,
      join: m in Marble,
      on: m.id == um.marble_id,
      where: um.user_id == ^user_id and um.id in ^ids,
      select: %{level: um.level, rarity: m.rarity}
    )
    |> Repo.all()
  end

  defp marble_hour_rate(%{level: level, rarity: rarity}) do
    r = min(3, max(1, rarity || 1))
    lv = max(1, level || 1)
    6.0 + lv * 1.4 + r * 3.0
  end
end
