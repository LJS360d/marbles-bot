defmodule Marbles.Racing.Events.Config do
  @moduledoc """
  Validates and normalizes the `config` blob attached to an `events` row.

  Owner backoffice writes this; the runner and eligibility checks read it.
  """

  @defaults %{
    "track_pool" => "any",
    "weather_pool" => "any",
    "atmosphere" => "auto",
    "min_marble_level" => 1,
    "team_whitelist" => [],
    "team_blacklist" => [],
    "elo_min" => 0,
    "elo_max" => 5_000,
    "entry_fee_coins" => 250,
    "max_participants" => 64,
    "pool_size" => 8,
    "payout_multiplier" => 1.5,
    "consolation_coins" => 50,
    "grade" => "C"
  }

  @spec defaults() :: map()
  def defaults, do: @defaults

  @spec normalize(map()) :: map()
  def normalize(input) when is_map(input) do
    @defaults
    |> Map.merge(stringify(input))
    |> Map.update("track_pool", "any", &normalize_pool/1)
    |> Map.update("weather_pool", "any", &normalize_pool/1)
    |> Map.update("team_whitelist", [], &normalize_list/1)
    |> Map.update("team_blacklist", [], &normalize_list/1)
    |> Map.update("min_marble_level", 1, &cast_integer(&1, 1))
    |> Map.update("elo_min", 0, &cast_integer(&1, 0))
    |> Map.update("elo_max", 5_000, &cast_integer(&1, 5_000))
    |> Map.update("entry_fee_coins", 250, &cast_integer(&1, 0))
    |> Map.update("max_participants", 64, &cast_integer(&1, 1))
    |> Map.update("pool_size", 8, &cast_integer(&1, 4))
    |> Map.update("payout_multiplier", 1.5, &cast_float(&1, 1.0))
    |> Map.update("consolation_coins", 50, &cast_integer(&1, 0))
  end

  defp stringify(map) do
    Enum.map(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  defp normalize_pool("any"), do: "any"
  defp normalize_pool([]), do: "any"
  defp normalize_pool(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_pool(_), do: "any"

  defp normalize_list(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_list(_), do: []

  defp cast_integer(v, _default) when is_integer(v), do: v

  defp cast_integer(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp cast_integer(_v, default), do: default

  defp cast_float(v, _default) when is_number(v), do: v / 1

  defp cast_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp cast_float(_v, default), do: default
end
