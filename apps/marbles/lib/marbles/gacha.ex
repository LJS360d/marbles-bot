defmodule Marbles.Gacha do
  alias Marbles.{Catalog, Analytics}
  require Logger

  @weights %{
    1 => 900,
    2 => 95,
    3 => 5
  }

  def pull_from_pack(pack_id, user_id, guild_id, opts \\ []) do
    case do_pull_from_pack(pack_id, opts) do
      {:ok, {marble, _}} ->
        Analytics.record_pull(guild_id, user_id, %{
          "pack_id" => to_string(pack_id),
          "marble_id" => to_string(marble.id)
        })

        {:ok, marble}

      other ->
        other
    end
  end

  def pull_10_from_pack(pack_id, user_id, guild_id, opts \\ []) do
    all_min = Keyword.get(opts, :all_min_rarity)
    first_min = Keyword.get(opts, :first_min_rarity)

    result =
      1..10
      |> Enum.reduce_while([], fn i, acc ->
        min_r =
          cond do
            all_min -> all_min
            i == 1 && first_min -> first_min
            true -> nil
          end

        case do_pull_from_pack(pack_id, min_rarity: min_r) do
          {:ok, marble} ->
            Analytics.record_pull(guild_id, user_id, %{
              "pack_id" => to_string(pack_id),
              "marble_id" => to_string(marble.id)
            })

            {:cont, [marble | acc]}

          {:error, _} = e ->
            {:halt, e}
        end
      end)

    case result do
      {:error, _} = e -> e
      marbles when is_list(marbles) -> {:ok, Enum.reverse(marbles)}
    end
  end

  def pick_rarity do
    weighted_pick(@weights)
  end

  defp pick_rarity_at_least(min_r) when is_integer(min_r) and min_r >= 1 do
    w =
      @weights
      |> Enum.filter(fn {r, _} -> r >= min_r end)
      |> Map.new()

    if map_size(w) == 0 do
      pick_rarity()
    else
      weighted_pick(w)
    end
  end

  defp weighted_pick(weights) when is_map(weights) do
    total = Enum.reduce(weights, 0, fn {_, v}, acc -> acc + v end)
    target = :rand.uniform(total)

    Enum.reduce_while(weights, 0, fn {rarity, weight}, acc ->
      if target <= acc + weight,
        do: {:halt, rarity},
        else: {:cont, acc + weight}
    end)
  end

  def spawn_marble(guild_id, channel_id) do
    case do_spawn_marble() do
      {:ok, spawned} ->
        Analytics.record_spawn(guild_id, channel_id, nil, %{"marble_id" => to_string(spawned.id)})
        {:ok, spawned}

      other ->
        other
    end
  end

  defp do_pull_from_pack(pack_id, opts) do
    rarity =
      case Keyword.get(opts, :min_rarity) do
        nil -> pick_rarity()
        m when is_integer(m) -> pick_rarity_at_least(m)
        _ -> pick_rarity()
      end

    marbles = Catalog.list_pack_marbles_by_rarity(pack_id, rarity)
    pool = marbles |> Enum.map(fn marble -> {marble, @weights[marble.rarity]} end)

    case pool do
      [] ->
        Logger.error("Gacha Error: No marbles found for pack #{pack_id}")
        {:error, :empty_pool}

      marbles ->
        selected_marble = Enum.random(marbles)
        {:ok, selected_marble}
    end
  end

  defp do_spawn_marble do
    marbles = Catalog.list_marbles_in_active_packs()

    case marbles do
      [] ->
        {:error, :empty_pool}

      _ ->
        rarity = pick_rarity()
        pool = Enum.filter(marbles, &(&1.rarity == rarity))
        chosen = if pool == [], do: Enum.random(marbles), else: Enum.random(pool)
        {:ok, chosen}
    end
  end
end
