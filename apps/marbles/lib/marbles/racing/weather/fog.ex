defmodule Marbles.Racing.Weather.Fog do
  @moduledoc "Fog: visibility-only effect, neutral grip."
  @behaviour Marbles.Racing.Weather.Effect

  @impl true
  def key, do: :fog

  @impl true
  def name, do: "Fog"

  @impl true
  def modifiers,
    do: %{grip: 0.96, visibility: 0.55, top_speed: 0.96, stamina_drain: 1.0}

  @impl true
  def rarity, do: 2
end
