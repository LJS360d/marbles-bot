defmodule Marbles.Racing.Weather.Effect do
  @moduledoc "Behaviour for weather modules."

  @callback key() :: atom()
  @callback name() :: String.t()
  @callback modifiers() :: %{
              grip: float(),
              visibility: float(),
              top_speed: float(),
              stamina_drain: float()
            }
  @callback rarity() :: pos_integer()
end
