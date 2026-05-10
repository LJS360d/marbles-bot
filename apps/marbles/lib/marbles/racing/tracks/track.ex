defmodule Marbles.Racing.Tracks.Track do
  @moduledoc "Behaviour for code-defined race tracks."

  @callback slug() :: String.t()
  @callback name() :: String.t()
  @callback model_path() :: String.t()
  @callback length_meters() :: float()
  @callback laps() :: pos_integer()
  @callback grid_size() :: pos_integer()
  @callback weather_bias() :: %{atom() => float()}
end
