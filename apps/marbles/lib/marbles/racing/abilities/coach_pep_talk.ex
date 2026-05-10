defmodule Marbles.Racing.Abilities.CoachPepTalk do
  @moduledoc "Coach pulse: small recurring top-speed buff to own racers."
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :coach_pep_talk

  @impl true
  def name, do: "Pep Talk"

  @impl true
  def description, do: "Coach grants +3% top speed to own racers in periodic pulses."

  @impl true
  def kind, do: :active

  @impl true
  def triggers, do: [:coach_pulse]

  @impl true
  def rarity, do: 1

  @impl true
  def applicable?(:coach, _marble, _squad), do: true
  def applicable?(_role, _marble, _squad), do: false

  @impl true
  def apply(_ctx, marble), do: Map.put(marble, :__coach_buff_until_offset, 3.0)
end
