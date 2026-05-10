defmodule Marbles.Racing.Abilities.SecondWind do
  @moduledoc "Top-speed boost in the final 15% of the race."
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :second_wind

  @impl true
  def name, do: "Second Wind"

  @impl true
  def description, do: "+15% top speed in the final 15% of the race."

  @impl true
  def kind, do: :active

  @impl true
  def triggers, do: [:final_stretch, :tick]

  @impl true
  def rarity, do: 2

  @impl true
  def applicable?(:racer, _marble, _squad), do: true
  def applicable?(_role, _marble, _squad), do: false

  @impl true
  def apply(%{trigger: :final_stretch}, marble), do: Map.put(marble, :__second_wind, true)

  def apply(%{trigger: :tick}, %{__second_wind: true} = marble) do
    apply_modifier(marble, :top_speed, 1.15)
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
