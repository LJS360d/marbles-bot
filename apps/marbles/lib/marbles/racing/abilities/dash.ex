defmodule Marbles.Racing.Abilities.Dash do
  @moduledoc "Burst of acceleration in the opening 2 seconds of a race."
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :dash

  @impl true
  def name, do: "Dash"

  @impl true
  def description, do: "+30% acceleration for the first 2 seconds of the race."

  @impl true
  def kind, do: :active

  @impl true
  def triggers, do: [:race_start, :tick]

  @impl true
  def rarity, do: 1

  @impl true
  def applicable?(:racer, _marble, _squad), do: true
  def applicable?(_role, _marble, _squad), do: false

  @impl true
  def apply(%{trigger: :race_start}, marble), do: Map.put(marble, :__dash_until, 2.0)

  def apply(%{trigger: :tick, race: %{t: t}}, %{__dash_until: until} = marble) when t < until do
    apply_modifier(marble, :acceleration, 1.30)
  end

  def apply(_ctx, marble), do: marble

  defp apply_modifier(marble, key, mult) do
    Map.update(
      marble,
      :modifiers,
      %{key => mult},
      &Map.update(&1, key, mult, fn v -> v * mult end)
    )
  end
end
