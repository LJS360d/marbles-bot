defmodule Marbles.Racing.Weather do
  @moduledoc """
  Weather registry. Code-defined modules implement
  `Marbles.Racing.Weather.Effect`. Each track exposes a `weather_bias` map
  used to weight random sampling.
  """

  alias Marbles.Racing.Weather.{Clear, Fog, Hail, Rain, Snow}

  @modules [Clear, Rain, Snow, Hail, Fog]

  @type descriptor :: %{
          key: atom(),
          name: String.t(),
          modifiers: %{
            grip: float(),
            visibility: float(),
            top_speed: float(),
            stamina_drain: float()
          },
          rarity: pos_integer()
        }

  @spec all() :: [descriptor()]
  def all, do: Enum.map(@modules, &describe/1)

  @spec get(atom() | String.t()) :: descriptor() | nil
  def get(key) when is_atom(key) do
    case Enum.find(@modules, fn m -> m.key() == key end) do
      nil -> nil
      mod -> describe(mod)
    end
  end

  def get(key) when is_binary(key) do
    try do
      get(String.to_existing_atom(key))
    rescue
      ArgumentError -> nil
    end
  end

  @spec pick_random(:rand.state(), %{atom() => float()} | nil) ::
          {descriptor(), :rand.state()}
  def pick_random(rng, bias \\ nil) do
    weights =
      Enum.map(@modules, fn mod ->
        weight =
          case bias do
            nil -> 1.0
            map when is_map(map) -> Map.get(map, mod.key(), 0.5)
          end

        {mod, max(weight, 0.0)}
      end)

    {chosen, rng} = weighted_sample(weights, rng)
    {describe(chosen), rng}
  end

  defp weighted_sample(weights, rng) do
    total = Enum.reduce(weights, 0.0, fn {_m, w}, acc -> acc + w end)
    total = if total <= 0.0, do: 1.0, else: total
    {r, rng} = :rand.uniform_s(rng)
    target = r * total

    chosen =
      Enum.reduce_while(weights, {0.0, nil}, fn {mod, w}, {acc, _} ->
        new_acc = acc + w
        if target <= new_acc, do: {:halt, {new_acc, mod}}, else: {:cont, {new_acc, mod}}
      end)
      |> elem(1)
      |> Kernel.||(elem(List.first(weights), 0))

    {chosen, rng}
  end

  defp describe(mod) do
    %{
      key: mod.key(),
      name: mod.name(),
      modifiers: mod.modifiers(),
      rarity: mod.rarity()
    }
  end
end
