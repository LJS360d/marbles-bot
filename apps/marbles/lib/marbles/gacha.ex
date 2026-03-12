defmodule Marbles.Gacha do
  alias Marbles.{Catalog, Analytics}
  require Logger

  # Weighted probabilities (out of 1000 for precision)
  @weights %{
    1 => 900,
    2 => 95,
    3 => 5
  }

  def pull_from_pack(pack_id, user_id, guild_id) do
    case do_pull_from_pack(pack_id) do
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

  def pick_rarity do
    total = Enum.reduce(@weights, 0, fn {_, v}, acc -> acc + v end)
    target = :rand.uniform(total)

    Enum.reduce_while(@weights, 0, fn {rarity, weight}, acc ->
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

  defp do_pull_from_pack(pack_id) do
    rarity = pick_rarity()
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
