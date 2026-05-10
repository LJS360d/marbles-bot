defmodule Marbles.Racing.Weather.Hail do
  @moduledoc "Hail: brutal top-speed and stamina hit."
  @behaviour Marbles.Racing.Weather.Effect

  @impl true
  def key, do: :hail

  @impl true
  def name, do: "Hail"

  @impl true
  def modifiers,
    do: %{grip: 0.78, visibility: 0.7, top_speed: 0.9, stamina_drain: 1.20}

  @impl true
  def rarity, do: 3
end
