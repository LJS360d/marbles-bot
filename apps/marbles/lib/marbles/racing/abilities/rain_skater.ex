defmodule Marbles.Racing.Abilities.RainSkater do
  @moduledoc "Resists half of the rain grip penalty."
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :rain_skater

  @impl true
  def name, do: "Rain Skater"

  @impl true
  def description, do: "Ignores 50% of the grip penalty when racing in the rain."

  @impl true
  def kind, do: :passive

  @impl true
  def triggers, do: [:tick]

  @impl true
  def rarity, do: 2

  @impl true
  def applicable?(:racer, _marble, _squad), do: true
  def applicable?(_role, _marble, _squad), do: false

  @impl true
  def apply(%{race: %{weather: %{key: :rain, modifiers: %{grip: grip}}}}, marble) do
    recovery = (1.0 - grip) * 0.5
    apply_modifier(marble, :grip_offset, recovery)
  end

  def apply(_ctx, marble), do: marble

  defp apply_modifier(marble, key, value) do
    Map.update(marble, :modifiers, %{key => value}, &Map.put(&1, key, value))
  end
end
