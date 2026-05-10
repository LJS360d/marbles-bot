defmodule Marbles.Racing.Weather.Rain do
  @moduledoc "Rainy track: lower grip, slight top-speed reduction."
  @behaviour Marbles.Racing.Weather.Effect

  @impl true
  def key, do: :rain

  @impl true
  def name, do: "Rain"

  @impl true
  def modifiers,
    do: %{grip: 0.85, visibility: 0.85, top_speed: 0.97, stamina_drain: 1.05}

  @impl true
  def rarity, do: 2
end
