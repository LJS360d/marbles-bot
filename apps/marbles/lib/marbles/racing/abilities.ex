defmodule Marbles.Racing.Abilities do
  @moduledoc """
  Registry and resolution helpers for marble abilities.

  Each ability is a module implementing `Marbles.Racing.Abilities.Ability`.
  Abilities are referenced by their atom `key/0`. Engine code looks up
  applicable abilities for a marble at given trigger points and asks them
  to mutate a marble engine state.

  Adding a new ability:

      1. Create a module under `Marbles.Racing.Abilities.<Name>` implementing
         the `Ability` behaviour.
      2. Add it to `@modules` below.

  No DB migration is required. The `marble_abilities` table only stores
  ability *keys*; behaviour-side rules ensure unknown keys are ignored.
  """

  alias Marbles.Racing.Abilities.{
    CoachPepTalk,
    CoachStrategist,
    Dash,
    RainSkater,
    Rivalry,
    SecondWind,
    Slipstream,
    TeamSignature
  }

  @modules [
    Dash,
    SecondWind,
    Slipstream,
    RainSkater,
    Rivalry,
    CoachPepTalk,
    CoachStrategist
  ]

  @auto_modules [TeamSignature]

  @type trigger ::
          :race_start
          | :tick
          | :checkpoint
          | :overtake
          | :weather_change
          | :final_stretch
          | :rival_team_nearby
          | :coach_pulse

  @type role :: :racer | :coach
  @type marble_state :: map()
  @type race_state :: map()
  @type context :: %{
          required(:trigger) => trigger(),
          required(:role) => role(),
          required(:marble) => marble_state(),
          required(:race) => race_state(),
          optional(:rng) => :rand.state(),
          optional(:meta) => map()
        }

  @doc """
  All user-assignable abilities (those registered in `marble_abilities`).
  """
  @spec all() :: [module()]
  def all, do: @modules

  @doc """
  Abilities applied automatically by the engine regardless of DB state.
  """
  @spec auto() :: [module()]
  def auto, do: @auto_modules

  @doc """
  Look up an ability module by its key (atom or string).
  Returns nil for unknown keys (defensive: unknown keys are skipped).
  """
  @spec get(atom() | String.t()) :: module() | nil
  def get(key) when is_atom(key) do
    Enum.find(@modules ++ @auto_modules, fn mod -> mod.key() == key end)
  end

  def get(key) when is_binary(key) do
    case Enum.find(@modules ++ @auto_modules, fn mod ->
           Atom.to_string(mod.key()) == key
         end) do
      nil ->
        try do
          get(String.to_existing_atom(key))
        rescue
          ArgumentError -> nil
        end

      mod ->
        mod
    end
  end

  @doc """
  Modules listening for a given trigger and applicable to a (role, marble, squad).
  Used by the engine each tick.
  """
  @spec resolve(trigger(), role(), map(), map()) :: [module()]
  def resolve(trigger, role, marble, squad) do
    keys = MapSet.new(Map.get(marble, :ability_keys, []))

    @modules
    |> Enum.filter(fn mod ->
      trigger in mod.triggers() and
        MapSet.member?(keys, mod.key()) and
        mod.applicable?(role, marble, squad)
    end)
  end
end
