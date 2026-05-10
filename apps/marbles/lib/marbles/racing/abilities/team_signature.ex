defmodule Marbles.Racing.Abilities.TeamSignature do
  @moduledoc """
  Automatic squad-wide bonus computed at race start.

  Counts how many of (3 racers + coach) share each racer's `team_id`.
  Returns the bonus as `{accel_mult, top_speed_mult}` per racer.

  Teamless marbles (`team_id == nil`) get no signature bonus by design;
  they are tuned around special abilities and special-event modes.
  """
  @behaviour Marbles.Racing.Abilities.Ability

  @impl true
  def key, do: :team_signature

  @impl true
  def name, do: "Team Signature"

  @impl true
  def description,
    do: "Stacking +acceleration / +top speed when squadmates share your team."

  @impl true
  def kind, do: :passive

  @impl true
  def triggers, do: [:race_start]

  @impl true
  def rarity, do: 1

  @impl true
  def applicable?(_role, _marble, _squad), do: true

  @impl true
  def apply(%{role: :racer, marble: %{team_id: nil}}, marble), do: marble

  def apply(%{role: :racer, marble: %{team_id: tid}, meta: %{squad_team_ids: ids}}, marble)
      when not is_nil(tid) do
    same = Enum.count(ids, &(&1 == tid))
    {accel_mult, top_mult} = signature_bonus(same)

    marble
    |> apply_modifier(:acceleration, accel_mult)
    |> apply_modifier(:top_speed, top_mult)
  end

  def apply(_ctx, marble), do: marble

  defp signature_bonus(same_count) do
    cond do
      same_count >= 4 -> {1.09, 1.09}
      same_count == 3 -> {1.05, 1.05}
      same_count == 2 -> {1.02, 1.02}
      true -> {1.0, 1.0}
    end
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
