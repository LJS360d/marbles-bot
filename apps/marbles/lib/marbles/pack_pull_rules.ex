defmodule Marbles.PackPullRules do
  @moduledoc false

  alias Marbles.Repo
  alias Marbles.Schema.{UserPackPullRuleState, Pack}
  import Ecto.Query

  def active_rules(%Pack{pull_rules: list}) when is_list(list) do
    now = DateTime.utc_now()

    list
    |> Enum.filter(fn r ->
      (is_nil(r.starts_at) or DateTime.compare(now, r.starts_at) != :lt) and
        (is_nil(r.ends_at) or DateTime.compare(now, r.ends_at) != :gt)
    end)
    |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
  end

  def active_rules(_), do: []

  defp pity_rules_active(%Pack{} = pack) do
    active_rules(pack) |> Enum.filter(&(&1.effect_type == "pity"))
  end

  def pity_force_min_rarity(user_id, %Pack{} = pack) do
    rules = pity_rules_active(pack)

    if rules == [] do
      nil
    else
      ids = Enum.map(rules, & &1.id)
      states = load_states(user_id, ids)

      mrs =
        for rule <- rules,
            n = rule.every_n_pulls || 1,
            mr = rule.min_rarity || 1,
            streak = Map.get(states, rule.id, %{acc: 0})[:acc] || 0,
            streak >= n - 1,
            do: mr

      case mrs do
        [] -> nil
        list -> Enum.max(list)
      end
    end
  end

  def commit_pity_after_marble!(user_id, pack_id, marble_rarity) when is_integer(marble_rarity) do
    pack = Repo.get!(Pack, pack_id) |> Repo.preload(:pull_rules)
    rules = pity_rules_active(pack)

    if rules == [] do
      :ok
    else
      ids = Enum.map(rules, & &1.id)
      states = load_states(user_id, ids)

      Enum.each(rules, fn rule ->
        mr = rule.min_rarity || 1
        streak = Map.get(states, rule.id, %{acc: 0})[:acc] || 0

        new_streak =
          if marble_rarity >= mr, do: 0, else: streak + 1

        upsert_state(user_id, rule.id, %{pulls_accumulated: new_streak})
      end)

      :ok
    end
  end

  def quote_one(user_id, %Pack{} = pack) do
    base = pack.cost || 0
    do_quote(user_id, pack, base, 1, :one)
  end

  def quote_ten(user_id, %Pack{} = pack) do
    base = 10 * (pack.cost || 0)
    do_quote(user_id, pack, base, 10, :ten)
  end

  defp do_quote(user_id, pack, base, weight, kind) do
    rules =
      active_rules(pack)
      |> Enum.filter(fn r ->
        r.effect_type == "discount" and
          ((kind == :one and r.apply_1x) or (kind == :ten and r.apply_10x))
      end)

    rule_ids = Enum.map(rules, & &1.id)
    states = load_states(user_id, rule_ids)

    price =
      Enum.reduce(rules, base, fn rule, p ->
        st = Map.get(states, rule.id, %{uses: 0, period: nil, acc: 0})

        if trigger_fires?(rule, st, weight, kind) do
          apply_disc(rule.discount_percent, p)
        else
          p
        end
      end)

    %{
      base_price: base,
      final_price: price,
      weight: weight,
      pull_kind: kind
    }
  end

  defp trigger_fires?(%{trigger_type: "always"}, _, _, _), do: true

  defp trigger_fires?(%{trigger_type: "lifetime_uses"} = r, st, _, _) do
    (st[:uses] || 0) < (r.lifetime_max_uses || 0)
  end

  defp trigger_fires?(%{trigger_type: "period_once", period_unit: u}, st, _, _) do
    cur = current_period_bucket(u)
    st[:period] != cur
  end

  defp trigger_fires?(%{trigger_type: "every_n_pulls"} = r, st, w, kind) do
    applies = (kind == :one and r.apply_1x) or (kind == :ten and r.apply_10x)
    n = r.every_n_pulls || 10
    applies && (st[:acc] || 0) + w >= n
  end

  defp trigger_fires?(_, _, _, _), do: false

  defp current_period_bucket("day"), do: Date.utc_today() |> Date.to_iso8601()

  defp current_period_bucket("week") do
    d = Date.utc_today()
    {wy, ww} = :calendar.iso_week_number({d.year, d.month, d.day})
    "#{wy}-W#{String.pad_leading(to_string(ww), 2, "0")}"
  end

  defp current_period_bucket("month") do
    d = Date.utc_today()
    "#{d.year}-#{String.pad_leading(to_string(d.month), 2, "0")}"
  end

  defp current_period_bucket(_), do: Date.utc_today() |> Date.to_iso8601()

  defp apply_disc(0, p), do: p
  defp apply_disc(d, p), do: div(p * (100 - min(100, d)) + 99, 100)

  defp load_states(user_id, rule_ids) do
    if rule_ids == [] do
      %{}
    else
      from(s in UserPackPullRuleState,
        where: s.user_id == ^user_id and s.rule_id in ^rule_ids
      )
      |> Repo.all()
      |> Map.new(fn s ->
        {s.rule_id,
         %{
           uses: s.uses_consumed || 0,
           period: s.period_bucket,
           acc: s.pulls_accumulated || 0
         }}
      end)
    end
  end

  def commit_after_one_pull!(user_id, pack_id, quote) do
    commit_after_pull!(user_id, pack_id, quote)
  end

  def commit_after_ten_pull!(user_id, pack_id, quote) do
    commit_after_pull!(user_id, pack_id, quote)
  end

  defp commit_after_pull!(user_id, pack_id, %{weight: w, pull_kind: kind}) do
    pack = Repo.get!(Pack, pack_id) |> Repo.preload(:pull_rules)
    rules = active_rules(pack)

    discount_every_n =
      Enum.filter(rules, fn r ->
        r.effect_type == "discount" and r.trigger_type == "every_n_pulls"
      end)

    all_ids = Enum.map(rules, & &1.id)
    states = load_states(user_id, all_ids)

    Repo.transaction(fn ->
      Enum.each(discount_every_n, fn rule ->
        st = Map.get(states, rule.id, %{uses: 0, period: nil, acc: 0})
        n = rule.every_n_pulls || 10
        applies = (kind == :one and rule.apply_1x) or (kind == :ten and rule.apply_10x)
        acc = st.acc
        added = acc + w

        new_acc =
          if applies && added >= n do
            added - n
          else
            added
          end

        upsert_state(user_id, rule.id, %{pulls_accumulated: new_acc})
      end)

      fired = rules_for_kind(rules, kind)

      Enum.each(fired, fn rule ->
        next_st = get_state_after_every_n(user_id, rule.id, w, kind, rule, states)

        if trigger_fires_with_state?(rule, next_st, w, kind) do
          case rule.trigger_type do
            "lifetime_uses" ->
              st2 = Map.get(states, rule.id, %{uses: 0, period: nil, acc: 0})
              upsert_state(user_id, rule.id, %{uses_consumed: st2[:uses] + 1})

            "period_once" ->
              upsert_state(user_id, rule.id, %{
                period_bucket: current_period_bucket(rule.period_unit)
              })

            _ ->
              :ok
          end
        end
      end)

      :ok
    end)
  end

  defp rules_for_kind(rules, :one), do: Enum.filter(rules, & &1.apply_1x)
  defp rules_for_kind(rules, :ten), do: Enum.filter(rules, & &1.apply_10x)

  defp get_state_after_every_n(_user_id, rule_id, w, kind, rule, states) do
    if rule.effect_type != "discount" or rule.trigger_type != "every_n_pulls" do
      Map.get(states, rule_id, %{uses: 0, period: nil, acc: 0})
    else
      st = Map.get(states, rule_id, %{uses: 0, period: nil, acc: 0})
      n = rule.every_n_pulls || 10
      applies = (kind == :one and rule.apply_1x) or (kind == :ten and rule.apply_10x)
      added = st.acc + w

      acc_after =
        if applies && added >= n do
          added - n
        else
          added
        end

      %{st | acc: acc_after}
    end
  end

  defp trigger_fires_with_state?(%{trigger_type: "always"}, _, _, _), do: true

  defp trigger_fires_with_state?(%{trigger_type: "lifetime_uses"} = r, st, _, _) do
    (st[:uses] || 0) < (r.lifetime_max_uses || 0)
  end

  defp trigger_fires_with_state?(%{trigger_type: "period_once", period_unit: u}, st, _, _) do
    st[:period] != current_period_bucket(u)
  end

  defp trigger_fires_with_state?(%{trigger_type: "every_n_pulls"} = r, st, w, kind) do
    applies = (kind == :one and r.apply_1x) or (kind == :ten and r.apply_10x)
    n = r.every_n_pulls || 10
    applies && (st[:acc] || 0) + w >= n
  end

  defp trigger_fires_with_state?(_, _, _, _), do: false

  defp upsert_state(user_id, rule_id, patch) do
    st =
      Repo.get_by(UserPackPullRuleState, user_id: user_id, rule_id: rule_id) ||
        %UserPackPullRuleState{
          user_id: user_id,
          rule_id: rule_id,
          uses_consumed: 0,
          pulls_accumulated: 0
        }

    attrs = %{
      user_id: user_id,
      rule_id: rule_id,
      uses_consumed: Map.get(patch, :uses_consumed, st.uses_consumed || 0),
      period_bucket: Map.get(patch, :period_bucket, st.period_bucket),
      pulls_accumulated: Map.get(patch, :pulls_accumulated, st.pulls_accumulated || 0)
    }

    if st.id do
      st |> UserPackPullRuleState.changeset(attrs) |> Repo.update!()
    else
      %UserPackPullRuleState{user_id: user_id, rule_id: rule_id}
      |> UserPackPullRuleState.changeset(attrs)
      |> Repo.insert!()
    end
  end

  def validate_rule_rows(rows) do
    pity_rows =
      Enum.filter(rows, fn r ->
        (r[:effect_type] || r["effect_type"]) == "pity"
      end)

    by_mr =
      Enum.group_by(pity_rows, fn r ->
        parse_int_nil(r["min_rarity"] || r[:min_rarity])
      end)

    cond do
      Map.has_key?(by_mr, nil) ->
        {:error, "Each pity rule must set min rarity (star tier)."}

      Enum.any?(by_mr, fn {_mr, list} -> length(list) > 1 end) ->
        {:error, "At most one pity rule per min rarity (e.g. one for ★2+, one for ★3+)."}

      true ->
        :ok
    end
  end

  def rules_summary_text(pack) do
    case active_rules(pack) do
      [] ->
        "Standard pricing only."

      rules ->
        rules
        |> Enum.map(&describe_rule/1)
        |> Enum.map(&("• " <> &1))
        |> Enum.join("\n")
    end
  end

  defp describe_rule(%{effect_type: "pity"} = r) do
    n = r.every_n_pulls || 0
    mr = r.min_rarity || 3
    "Guaranteed #{rarity_stars_string(mr)} every #{n} pulls"
  end

  defp describe_rule(r) do
    scope =
      cond do
        r.apply_1x and r.apply_10x -> "1× & 10×"
        r.apply_1x -> "1× pull"
        r.apply_10x -> "10× pull"
        true -> "—"
      end

    eff = effect_hint(r)

    trig =
      case r.trigger_type do
        "always" -> "always"
        "lifetime_uses" -> "Max #{r.lifetime_max_uses} times per account"
        "period_once" -> "Once per #{r.period_unit}"
        "every_n_pulls" -> "Every #{r.every_n_pulls} pulls"
        _ -> r.trigger_type
      end

    "#{trig} #{eff} #{scope}"
  end

  def row_attrs(pack_id, row) do
    t = row["trigger_type"] || row[:trigger_type]
    e = row["effect_type"] || row[:effect_type]

    {t, e} =
      if e == "pity" do
        {"every_n_pulls", "pity"}
      else
        {t, e}
      end

    %{
      pack_id: pack_id,
      effect_type: e,
      discount_percent: parse_int(row["discount_percent"] || row[:discount_percent], 0),
      min_rarity: parse_int_nil(row["min_rarity"] || row[:min_rarity]),
      apply_1x: scope_apply_1x(row, e),
      apply_10x: scope_apply_10x(row, e),
      trigger_type: t,
      lifetime_max_uses: parse_int_nil(row["lifetime_max_uses"] || row[:lifetime_max_uses]),
      period_unit: empty_to_nil(row["period_unit"] || row[:period_unit]),
      every_n_pulls: parse_int_nil(row["every_n_pulls"] || row[:every_n_pulls]),
      starts_at: parse_dt(row["starts_at"] || row[:starts_at]),
      ends_at: parse_dt(row["ends_at"] || row[:ends_at])
    }
  end

  defp scope_apply_1x(_row, "pity"), do: true

  defp scope_apply_1x(row, _) do
    s = to_string(row["scope"] || row[:scope] || "both")
    s in ["both", "1x_only"]
  end

  defp scope_apply_10x(_row, "pity"), do: true

  defp scope_apply_10x(row, _) do
    s = to_string(row["scope"] || row[:scope] || "both")
    s in ["both", "10x_only"]
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(s), do: s

  defp parse_int(nil, d), do: d

  defp parse_int(v, d) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} -> i
      :error -> d
    end
  end

  defp parse_int(v, _) when is_integer(v), do: v
  defp parse_int(_, d), do: d

  defp parse_int_nil(nil), do: nil
  defp parse_int_nil(""), do: nil

  defp parse_int_nil(v), do: parse_int(v, nil)

  defp parse_dt(nil), do: nil
  defp parse_dt(""), do: nil
  defp parse_dt(%DateTime{} = dt), do: dt

  defp parse_dt(s) when is_binary(s) do
    s = String.trim(s)
    if s == "", do: nil, else: datetime_from_input(s)
  end

  defp parse_dt(_), do: nil

  defp datetime_from_input(s) do
    case NaiveDateTime.from_iso8601(s <> ":00") do
      {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
      _ -> date_only(s)
    end
  end

  defp date_only(s) do
    case Date.from_iso8601(s) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> nil
    end
  end

  def one_pull_button_label(pack, user_id) do
    q = quote_one(user_id, pack)
    cost = pack.cost || 0
    coin = "🪙"
    rules = active_rules(pack) |> Enum.filter(& &1.apply_1x)

    cond do
      q.final_price == 0 and cost > 0 ->
        truncate_btn("Pull x1 FREE")

      q.final_price < cost ->
        truncate_btn("Pull x1 #{q.final_price}#{coin} (−#{q.base_price - q.final_price})")

      true ->
        suffix = countdown_suffix_1x(pack, user_id, rules)
        base = "Pull x1 #{cost}#{coin}"
        truncate_btn(if suffix != "", do: base <> " " <> suffix, else: base)
    end
  end

  def ten_pull_button_label(pack, user_id) do
    q = quote_ten(user_id, pack)
    base_p = q.base_price
    coin = "🪙"
    rules = active_rules(pack) |> Enum.filter(& &1.apply_10x)

    cond do
      q.final_price == 0 and base_p > 0 ->
        truncate_btn("Pull x10 FREE")

      q.final_price < base_p ->
        truncate_btn("Pull x10 #{q.final_price}#{coin} (−#{base_p - q.final_price})")

      true ->
        suffix = countdown_suffix_10x(pack, user_id, rules)
        b = "Pull x10 #{base_p}#{coin}"
        truncate_btn(if suffix != "", do: b <> " " <> suffix, else: b)
    end
  end

  def pity_guarantee_line(%Pack{} = pack, user_id) do
    rules = pity_rules_active(pack)

    if rules == [] do
      nil
    else
      ids = Enum.map(rules, & &1.id)
      states = load_states(user_id, ids)

      rules
      |> Enum.map(fn rule ->
        n = rule.every_n_pulls || 1
        mr = rule.min_rarity || 1
        streak = Map.get(states, rule.id, %{acc: 0})[:acc] || 0
        left = max(1, n - streak)
        "#{rarity_stars_string(mr)} guaranteed in #{left}"
      end)
      |> Enum.join("\n")
    end
  end

  defp rarity_stars_string(rarity) do
    r = min(3, max(1, rarity || 1))
    String.duplicate("⭐", r) <> String.duplicate("☆", 3 - r)
  end

  defp countdown_suffix_1x(_pack, user_id, rules) do
    states = load_states(user_id, Enum.map(rules, & &1.id))

    parts =
      Enum.flat_map(rules, fn r ->
        case r.trigger_type do
          "period_once" ->
            st = Map.get(states, r.id, %{uses: 0, period: nil, acc: 0})

            if st[:period] == current_period_bucket(r.period_unit) do
              sec = seconds_until_period_end(r.period_unit)
              ["(#{effect_hint(r)} in #{format_eta(sec)})"]
            else
              []
            end

          "every_n_pulls" ->
            if r.apply_1x and r.effect_type == "discount" do
              n = r.every_n_pulls || 10
              st = Map.get(states, r.id, %{acc: 0})
              left = max(0, n - st[:acc])
              if left > 0, do: ["(#{effect_hint(r)} after #{left} toward discount)"], else: []
            else
              []
            end

          _ ->
            []
        end
      end)

    Enum.join(parts, " ")
  end

  defp countdown_suffix_10x(_pack, user_id, rules) do
    states = load_states(user_id, Enum.map(rules, & &1.id))
    w = 10

    parts =
      Enum.flat_map(rules, fn r ->
        case r.trigger_type do
          "period_once" ->
            st = Map.get(states, r.id, %{period: nil})

            if st[:period] == current_period_bucket(r.period_unit) do
              sec = seconds_until_period_end(r.period_unit)
              ["(#{effect_hint(r)} in #{format_eta(sec)})"]
            else
              []
            end

          "every_n_pulls" ->
            if r.apply_10x and r.effect_type == "discount" do
              n = r.every_n_pulls || 10
              st = Map.get(states, r.id, %{acc: 0})
              left = max(0, n - st[:acc] - w)

              if st[:acc] + w < n,
                do: ["(#{effect_hint(r)} after #{left} more toward discount)"],
                else: []
            else
              []
            end

          _ ->
            []
        end
      end)

    Enum.join(parts, " ")
  end

  defp effect_hint(%{effect_type: "discount", discount_percent: 100}), do: "FREE"
  defp effect_hint(%{effect_type: "discount", discount_percent: d}), do: "#{d}% off"

  defp seconds_until_period_end("day") do
    t = Date.utc_today() |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    max(0, DateTime.diff(t, DateTime.utc_now(), :second))
  end

  defp seconds_until_period_end("month") do
    d = Date.utc_today()

    next =
      case d.month do
        12 -> Date.new!(d.year + 1, 1, 1)
        m -> Date.new!(d.year, m + 1, 1)
      end

    t = DateTime.new!(next, ~T[00:00:00], "Etc/UTC")
    max(0, DateTime.diff(t, DateTime.utc_now(), :second))
  end

  defp seconds_until_period_end(_) do
    days_to_mon = 7 - Date.day_of_week(Date.utc_today())
    days_to_mon = if days_to_mon <= 0, do: 7 + days_to_mon, else: days_to_mon
    t = Date.utc_today() |> Date.add(days_to_mon) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    max(0, DateTime.diff(t, DateTime.utc_now(), :second))
  end

  defp format_eta(sec) when sec < 3600, do: "#{div(sec, 60)}m"
  defp format_eta(sec) when sec < 86_400, do: "#{div(sec, 3600)}h"
  defp format_eta(sec), do: "#{div(sec, 86_400)}d"

  defp truncate_btn(s) do
    if String.length(s) <= 80, do: s, else: String.slice(s, 0, 77) <> "..."
  end
end
