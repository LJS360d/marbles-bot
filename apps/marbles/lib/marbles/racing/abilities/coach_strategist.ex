defmodule Marbles.Racing.Abilities.CoachStrategist do
  @moduledoc "Coach passive: opening acceleration buff for own racers."
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :coach_strategist

  @impl true
  def name, do: "Strategist"

  @impl true
  def description, do: "Coach grants own racers +5% acceleration for the first 5 seconds."

  @impl true
  def kind, do: :passive

  @impl true
  def triggers, do: [:race_start]

  @impl true
  def rarity, do: 2

  @impl true
  def applicable?(:coach, _marble, _squad), do: true
  def applicable?(_role, _marble, _squad), do: false

  @impl true
  def apply(_ctx, marble), do: Map.put(marble, :__strategist_until, 5.0)
end
