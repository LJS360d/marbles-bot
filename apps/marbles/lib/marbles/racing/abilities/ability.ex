defmodule Marbles.Racing.Abilities.Ability do
  @moduledoc """
  Behaviour every ability module must implement.

  See `Marbles.Racing.Abilities` for the registry.
  """

  alias Marbles.Racing.Abilities

  @callback key() :: atom()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback kind() :: :passive | :active
  @callback triggers() :: [Abilities.trigger()]
  @callback rarity() :: 1..3
  @callback applicable?(Abilities.role(), map(), map()) :: boolean()
  @callback apply(Abilities.context(), map()) :: map()
end
