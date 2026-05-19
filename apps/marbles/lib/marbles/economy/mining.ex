defmodule Marbles.Economy.Mining do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.{UserMarble, Marble}
  alias Marbles.Economy.{MineRoster, Upgrades, Effects}

  @base_offline_hours 36

  @spec max_accrual_seconds(Ecto.UUID.t()) :: pos_integer()
  def max_accrual_seconds(user_id) do
    extra_h =
      Upgrades.mine_extra_offline_hours(user_id) + Effects.mine_offline_cap_bonus_hours(user_id)

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
          roster_size: non_neg_integer(),
          breakdown: [
            %{
              user_marble_id: Ecto.UUID.t(),
              name: String.t(),
              rarity: pos_integer(),
              level: pos_integer(),
              coins: non_neg_integer()
            }
          ]
        }
  def compute_coins(user_id, accrual_seconds)
      when is_integer(accrual_seconds) and accrual_seconds >= 0 do
    roster_ids = MineRoster.list_assigned_user_marble_ids(user_id)
    cap = max_accrual_seconds(user_id)

    roster =
      if roster_ids == [] do
        []
      else
        load_roster(user_id, roster_ids)
      end

    roster_size = length(roster)

    cond do
      roster_ids == [] ->
        %{coins: 0, seconds: accrual_seconds, cap_seconds: cap, roster_size: 0, breakdown: []}

      roster == [] ->
        %{coins: 0, seconds: accrual_seconds, cap_seconds: cap, roster_size: 0, breakdown: []}

      accrual_seconds == 0 ->
        %{
          coins: 0,
          seconds: 0,
          cap_seconds: cap,
          roster_size: roster_size,
          breakdown:
            Enum.map(roster, fn r ->
              %{
                user_marble_id: r.user_marble_id,
                name: r.name,
                rarity: r.rarity || 1,
                level: max(1, r.level || 1),
                coins: 0
              }
            end)
        }

      true ->
        hours = accrual_seconds / 3600.0

        per_marble_base =
          Enum.map(roster, fn r ->
            %{
              user_marble_id: r.user_marble_id,
              name: r.name,
              rarity: r.rarity || 1,
              level: max(1, r.level || 1),
              base_coins: hours * marble_hour_rate(r)
            }
          end)

        total_base = per_marble_base |> Enum.map(& &1.base_coins) |> Enum.sum()

        yield_mult =
          (100 + Upgrades.mine_yield_percent(user_id) + Effects.mine_yield_bonus_percent(user_id)) /
            100.0

        coins = trunc(total_base * yield_mult) |> max(0)

        breakdown =
          per_marble_base
          |> Enum.map(fn r ->
            %{
              user_marble_id: r.user_marble_id,
              name: r.name,
              rarity: r.rarity,
              level: r.level,
              coins: max(0, trunc(r.base_coins * yield_mult))
            }
          end)

        %{
          coins: coins,
          seconds: accrual_seconds,
          cap_seconds: cap,
          roster_size: roster_size,
          breakdown: breakdown
        }
    end
  end

  defp load_roster(user_id, ids) do
    from(um in UserMarble,
      join: m in Marble,
      on: m.id == um.marble_id,
      where: um.user_id == ^user_id and um.id in ^ids,
      select: %{user_marble_id: um.id, name: m.name, level: um.level, rarity: m.rarity}
    )
    |> Repo.all()
  end

  defp marble_hour_rate(%{level: level, rarity: rarity}) do
    r = min(3, max(1, rarity || 1))
    lv = max(1, level || 1)
    1.8 + lv * 0.4 + r * 0.9
  end
end
