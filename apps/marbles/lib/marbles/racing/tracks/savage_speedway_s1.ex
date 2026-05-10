defmodule Marbles.Racing.Tracks.SavageSpeedwayS1 do
  @moduledoc "Built-in legacy track. Backed by an existing static GLB asset."
  @behaviour Marbles.Racing.Tracks.Track

  @impl true
  def slug, do: "savage_speedway_s1"

  @impl true
  def name, do: "Savage Speedway · S1"

  @impl true
  def model_path, do: "/3d/tracks/savage_speedway_s1.glb"

  @impl true
  def length_meters, do: 1100.0

  @impl true
  def laps, do: 1

  @impl true
  def grid_size, do: 24

  @impl true
  def weather_bias,
    do: %{clear: 1.0, rain: 0.5, snow: 0.2, hail: 0.15, fog: 0.4}
end
