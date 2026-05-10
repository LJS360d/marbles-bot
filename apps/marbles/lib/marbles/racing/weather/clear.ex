defmodule Marbles.Racing.Weather.Clear do
  @moduledoc "Default weather: no penalties."
  @behaviour Marbles.Racing.Weather.Effect

  @impl true
  def key, do: :clear

  @impl true
  def name, do: "Clear"

  @impl true
  def modifiers,
    do: %{grip: 1.0, visibility: 1.0, top_speed: 1.0, stamina_drain: 1.0}

  @impl true
  def rarity, do: 1
end
