defmodule Marbles.Racing.Abilities.Slipstream do
  @moduledoc "Top-speed bonus when within 1.5m behind another marble."
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :slipstream

  @impl true
  def name, do: "Slipstream"

  @impl true
  def description, do: "+5% top speed while within 1.5m behind another marble."

  @impl true
  def kind, do: :passive

  @impl true
  def triggers, do: [:tick]

  @impl true
  def rarity, do: 1

  @impl true
  def applicable?(:racer, _marble, _squad), do: true
  def applicable?(_role, _marble, _squad), do: false

  @impl true
  def apply(%{race: race, marble: m}, marble) do
    ahead =
      Map.get(race, :marbles, [])
      |> Enum.any?(fn other ->
        other.id != m.id and other.position > m.position and other.position - m.position <= 1.5
      end)

    if ahead, do: apply_modifier(marble, :top_speed, 1.05), else: marble
  end

  defp apply_modifier(marble, key, mult) do
    Map.update(
      marble,
      :modifiers,
      %{key => mult},
      &Map.update(&1, key, mult, fn v -> v * mult end)
    )
  end
end
