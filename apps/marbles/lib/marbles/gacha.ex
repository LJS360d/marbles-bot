defmodule Marbles.Gacha do
  alias Marbles.{Catalog}
  require Logger

  # Weighted probabilities (out of 1000 for precision)
  @weights %{
    1 => 900,
    2 => 95,
    3 => 5
  }

  def pull_from_pack(pack_id) do
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

  def pick_rarity do
    total = Enum.reduce(@weights, 0, fn {_, v}, acc -> acc + v end)
    target = :rand.uniform(total)

    # Walk through weights to find where the target lands
    Enum.reduce_while(@weights, 0, fn {rarity, weight}, acc ->
      if target <= acc + weight,
        do: {:halt, rarity},
        else: {:cont, acc + weight}
    end)
  end
end
