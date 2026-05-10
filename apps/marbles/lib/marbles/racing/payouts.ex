defmodule Marbles.Racing.Payouts do
  @moduledoc """
  Pure functions for race payouts and ELO updates.

  All math is deterministic and side-effect-free; persistence happens in
  callers (engine on race finish, events runner on event finish).
  """

  @type participant :: %{
          required(:user_id) => Ecto.UUID.t(),
          required(:elo) => integer(),
          required(:wage) => non_neg_integer()
        }

  @type result :: %{
          required(:user_id) => Ecto.UUID.t(),
          required(:position) => pos_integer()
        }

  @type payout :: %{
          required(:user_id) => Ecto.UUID.t(),
          required(:position) => pos_integer(),
          required(:payout) => non_neg_integer(),
          required(:elo_before) => integer(),
          required(:elo_after) => integer()
        }

  @consolation_floor 0.4

  @doc """
  Quick race payouts.

  - Pot is the sum of all wages.
  - Each finisher gets a base share weighted by `1 / position` and adjusted
    by ELO delta vs field average (beating higher ELO pays more).
  - Every finisher gets at least `0.4 * wage` back (`@consolation_floor`).

  Returns the same number of payout rows as participants.
  """
  @spec compute_quick(
          participants :: [participant()],
          results :: [result()]
        ) :: [payout()]
  def compute_quick(participants, results) when length(participants) == length(results) do
    pot = Enum.reduce(participants, 0, fn p, acc -> acc + p.wage end)
    field_avg_elo = average_elo(participants)
    by_user = Map.new(participants, fn p -> {p.user_id, p} end)
    n = length(participants)

    raw =
      results
      |> Enum.map(fn %{user_id: uid, position: pos} ->
        p = Map.fetch!(by_user, uid)
        weight = position_weight(pos) * elo_modifier(p.elo, field_avg_elo, pos, n)
        {uid, pos, weight, p.wage, p.elo}
      end)

    total_weight = Enum.reduce(raw, 0.0, fn {_, _, w, _, _}, a -> a + w end)
    total_weight = if total_weight <= 0.0, do: 1.0, else: total_weight

    payouts_by_user =
      raw
      |> Enum.map(fn {uid, pos, w, wage, elo} ->
        share = floor(pot * (w / total_weight))
        floor_amt = floor(wage * @consolation_floor)
        coins = max(share, floor_amt)
        new_elo = update_elo(elo, pos, n, field_avg_elo)
        %{user_id: uid, position: pos, payout: coins, elo_before: elo, elo_after: new_elo}
      end)

    rebalance(payouts_by_user, pot, by_user)
  end

  defp rebalance(rows, pot, by_user) do
    sum = Enum.reduce(rows, 0, &(&2 + &1.payout))
    diff = pot - sum

    cond do
      diff == 0 ->
        rows

      diff > 0 ->
        case rows do
          [first | rest] -> [%{first | payout: first.payout + diff} | rest]
          [] -> rows
        end

      diff < 0 ->
        scale_down(rows, by_user, abs(diff))
    end
  end

  defp scale_down(rows, by_user, deficit) when deficit > 0 do
    sorted = Enum.sort_by(rows, & &1.payout, :desc)
    do_scale_down(sorted, by_user, deficit, [])
  end

  defp do_scale_down([], _by_user, _deficit, acc), do: Enum.reverse(acc)

  defp do_scale_down([row | rest], _by_user, deficit, acc) when deficit <= 0,
    do: Enum.reverse(acc) ++ [row | rest]

  defp do_scale_down([row | rest], by_user, deficit, acc) do
    %{wage: wage} = Map.fetch!(by_user, row.user_id)
    floor_amt = floor(wage * @consolation_floor)
    take = min(deficit, max(row.payout - floor_amt, 0))
    do_scale_down(rest, by_user, deficit - take, [%{row | payout: row.payout - take} | acc])
  end

  defp position_weight(pos) when pos > 0, do: 1.0 / pos
  defp position_weight(_), do: 0.0

  defp average_elo(parts) do
    case length(parts) do
      0 -> 1000.0
      n -> Enum.reduce(parts, 0, &(&2 + &1.elo)) / n
    end
  end

  defp elo_modifier(elo, avg, pos, n) do
    diff = elo - avg
    finished_top? = pos <= div(n, 2) + 1
    base = 1.0

    cond do
      diff < 0 and finished_top? -> base + min(0.6, abs(diff) / 400)
      diff > 0 and not finished_top? -> max(0.4, base - min(0.5, diff / 400))
      diff > 0 and finished_top? -> max(0.6, base - min(0.4, diff / 600))
      true -> base
    end
  end

  @doc """
  Updates a single participant's ELO using a simplified Elo-style formula
  averaged across all opponents in the race.
  """
  @spec update_elo(integer(), pos_integer(), pos_integer(), float()) :: integer()
  def update_elo(elo, position, total, field_avg) do
    score =
      cond do
        total <= 1 -> 0.5
        true -> (total - position) / (total - 1)
      end

    expected = 1.0 / (1.0 + :math.pow(10.0, (field_avg - elo) / 400.0))
    k = 24.0
    elo + round(k * (score - expected))
  end

  @doc """
  Event payouts. Sums per-pool finishes (lower aggregate position = better)
  and applies a multiplier on top of the entry fee pot.
  """
  @spec compute_event(participants :: [participant()], pool_results :: [[result()]]) :: [payout()]
  def compute_event(participants, pool_results) do
    flat = List.flatten(pool_results)

    aggregate =
      flat
      |> Enum.group_by(& &1.user_id)
      |> Enum.map(fn {uid, list} ->
        avg = Enum.sum(Enum.map(list, & &1.position)) / length(list)
        {uid, avg}
      end)
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.with_index(1)
      |> Enum.map(fn {{uid, _avg}, pos} -> %{user_id: uid, position: pos} end)

    compute_quick(participants, aggregate)
  end
end
