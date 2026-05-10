defmodule Marbles.Racing.Weather.Snow do
  @moduledoc "Snowy track: lowest grip and visibility."
  @behaviour Marbles.Racing.Weather.Effect

  @impl true
  def key, do: :snow

  @impl true
  def name, do: "Snow"

  @impl true
  def modifiers,
    do: %{grip: 0.75, visibility: 0.75, top_speed: 0.93, stamina_drain: 1.10}

  @impl true
  def rarity, do: 2
end
