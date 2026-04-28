defmodule Marbles.PullItemRewards do
  @moduledoc false

  @type reward_context :: %{
          required(:duplicate?) => boolean(),
          required(:rarity) => pos_integer(),
          required(:pull_kind) => :one | :ten,
          required(:pack_id) => Ecto.UUID.t()
        }

  @spec rewards_for_pull(reward_context()) :: [map()]
  def rewards_for_pull(ctx) when is_map(ctx) do
    Application.get_env(:marbles, :pull_item_rewards, [])
    |> Enum.flat_map(fn rule ->
      if rule_applies?(rule, ctx) do
        normalize_rewards(Map.get(rule, :rewards) || Map.get(rule, "rewards") || [])
      else
        []
      end
    end)
  end

  @spec rule_applies?(map(), reward_context()) :: boolean()
  defp rule_applies?(rule, ctx) do
    trigger = Map.get(rule, :trigger) || Map.get(rule, "trigger") || %{}
    pull_kinds = Map.get(rule, :pull_kinds) || Map.get(rule, "pull_kinds") || ["one", "ten"]
    packs = Map.get(rule, :pack_ids) || Map.get(rule, "pack_ids") || []
    kind = Atom.to_string(Map.fetch!(ctx, :pull_kind))

    trigger_applies?(trigger, ctx) and kind in pull_kinds and
      pack_applies?(packs, Map.fetch!(ctx, :pack_id))
  end

  @spec trigger_applies?(map(), reward_context()) :: boolean()
  defp trigger_applies?(trigger, ctx) do
    kind = Map.get(trigger, :kind) || Map.get(trigger, "kind") || "any_pull"
    rarity = max(1, Map.fetch!(ctx, :rarity))

    min_rarity =
      normalize_min_rarity(Map.get(trigger, :min_rarity) || Map.get(trigger, "min_rarity"))

    duplicate? = Map.fetch!(ctx, :duplicate?)

    case kind do
      "any_pull" ->
        rarity >= min_rarity

      "duplicate" ->
        duplicate? and rarity >= min_rarity

      "duplicate_rarity_at_least" ->
        duplicate? and rarity >= min_rarity

      "rarity_at_least" ->
        rarity >= min_rarity

      _ ->
        false
    end
  end

  @spec pack_applies?([String.t()], Ecto.UUID.t()) :: boolean()
  defp pack_applies?([], _pack_id), do: true

  defp pack_applies?(pack_ids, pack_id) when is_list(pack_ids) and is_binary(pack_id) do
    Enum.any?(pack_ids, &(to_string(&1) == to_string(pack_id)))
  end

  @spec normalize_rewards([map()]) :: [map()]
  defp normalize_rewards(rewards) when is_list(rewards) do
    rewards
    |> Enum.reduce([], fn reward, acc ->
      item_type = Map.get(reward, :item_type) || Map.get(reward, "item_type")
      item_id = Map.get(reward, :item_id) || Map.get(reward, "item_id")
      quantity = Map.get(reward, :quantity) || Map.get(reward, "quantity") || 0
      meta = Map.get(reward, :meta) || Map.get(reward, "meta") || %{}

      if is_binary(item_type) and item_type != "" and is_binary(item_id) and item_id != "" and
           is_integer(quantity) and quantity > 0 do
        [%{item_type: item_type, item_id: item_id, quantity: quantity, meta: meta} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  @spec normalize_min_rarity(integer() | String.t() | nil) :: pos_integer()
  defp normalize_min_rarity(nil), do: 1
  defp normalize_min_rarity(v) when is_integer(v), do: min(3, max(1, v))

  defp normalize_min_rarity(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {value, _} -> normalize_min_rarity(value)
      :error -> 1
    end
  end
end
