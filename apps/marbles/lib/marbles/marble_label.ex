defmodule Marbles.MarbleLabel do
  @moduledoc false

  alias Marbles.IntegerDisplay

  @spec stars(integer() | nil) :: String.t()
  def stars(rarity) do
    r = min(3, max(1, rarity || 1))
    String.duplicate("⭐", r) <> String.duplicate("☆", 3 - r)
  end

  @spec pull_line(%{required(:name) => String.t(), optional(:rarity) => integer() | nil}) ::
          String.t()
  def pull_line(%{name: name} = row) do
    r = Map.get(row, :rarity) || 1
    "#{name} · #{stars(r)}"
  end

  @spec owned_line(map()) :: String.t()
  def owned_line(%{name: name} = row) do
    lv =
      case Map.get(row, :level) do
        l when is_integer(l) -> max(1, l)
        _ -> 1
      end

    r = Map.get(row, :rarity) || 1
    "#{name} · Lv.#{IntegerDisplay.format(lv)} · #{stars(r)}"
  end
end
