defmodule Marbles.Racing.Abilities.Rivalry do
  @moduledoc "Acceleration boost when a rival-team marble is within 2m."
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :rivalry

  @impl true
  def name, do: "Rivalry"

  @impl true
  def description, do: "+10% acceleration while a rival-team marble is within 2m."

  @impl true
  def kind, do: :active

  @impl true
  def triggers, do: [:tick]

  @impl true
  def rarity, do: 2

  @impl true
  def applicable?(:racer, %{team_id: tid}, _squad), do: not is_nil(tid)
  def applicable?(_role, _marble, _squad), do: false

  @impl true
  def apply(%{race: race, marble: m}, marble) do
    rival? =
      Map.get(race, :marbles, [])
      |> Enum.any?(fn other ->
        other.id != m.id and
          not is_nil(other.team_id) and
          other.team_id != m.team_id and
          abs(other.position - m.position) <= 2.0
      end)

    if rival?, do: apply_modifier(marble, :acceleration, 1.10), else: marble
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
