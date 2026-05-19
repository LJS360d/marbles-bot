defmodule Marbles.Racing.Tracks do
  @moduledoc """
  Track registry. Tracks come from two sources:

  1. **Code-defined tracks** — modules implementing `Marbles.Racing.Tracks.Track`.
     Listed in `@modules` here. Adding a new built-in track means adding a
     module + an entry in `@modules`.
  2. **DB-defined tracks** — rows in `race_tracks` (created by the owner
     backoffice). DB rows always win over code modules with the same slug.

  All callers should use `get/1`, `all/0` or `pick_random/2` and never
  reach into `race_tracks` directly.
  """

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Racing.Tracks.SavageSpeedwayS1
  alias Marbles.Schema.RaceTrack

  @modules [SavageSpeedwayS1]

  @type descriptor :: %{
          source: :code | :db,
          slug: String.t(),
          name: String.t(),
          model_path: String.t(),
          thumbnail_path: String.t() | nil,
          length_meters: float(),
          laps: pos_integer(),
          grid_size: pos_integer(),
          weather_bias: %{atom() => float()},
          difficulty: pos_integer()
        }

  @spec all() :: [descriptor()]
  def all do
    db_descriptors = Repo.all(from(t in RaceTrack, where: t.active == true))

    db_slugs = MapSet.new(db_descriptors, & &1.slug)

    code_descriptors =
      @modules
      |> Enum.reject(fn mod -> MapSet.member?(db_slugs, mod.slug()) end)
      |> Enum.map(&from_module/1)

    Enum.map(db_descriptors, &from_db/1) ++ code_descriptors
  end

  @spec get(String.t()) :: descriptor() | nil
  def get(slug) when is_binary(slug) do
    case Repo.get_by(RaceTrack, slug: slug) do
      %RaceTrack{} = t ->
        from_db(t)

      nil ->
        case Enum.find(@modules, fn m -> m.slug() == slug end) do
          nil -> nil
          mod -> from_module(mod)
        end
    end
  end

  @doc """
  Picks a random track using the supplied seed and an optional pool of slugs.
  """
  @spec pick_random(:rand.state(), [String.t()] | nil) ::
          {descriptor(), :rand.state()} | nil
  def pick_random(rng, pool \\ nil) do
    candidates =
      case pool do
        nil -> all()
        [] -> all()
        slugs when is_list(slugs) -> slugs |> Enum.map(&get/1) |> Enum.reject(&is_nil/1)
      end

    case candidates do
      [] -> nil
      list -> sample(list, rng)
    end
  end

  defp sample(list, rng) do
    n = length(list)
    {idx, rng} = :rand.uniform_s(n, rng)
    {Enum.at(list, idx - 1), rng}
  end

  @doc "Lists all DB-defined track rows (including inactive). For admin use."
  @spec list_db_all() :: [RaceTrack.t()]
  def list_db_all do
    Repo.all(from(t in RaceTrack, order_by: [asc: t.name]))
  end

  @doc "Fetches a DB track row by id."
  @spec get_db(Ecto.UUID.t()) :: {:ok, RaceTrack.t()} | {:error, :not_found}
  def get_db(id) do
    case Repo.get(RaceTrack, id) do
      nil -> {:error, :not_found}
      t -> {:ok, t}
    end
  end

  @spec create(map()) :: {:ok, RaceTrack.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %RaceTrack{}
    |> RaceTrack.changeset(attrs)
    |> Repo.insert()
  end

  @spec update(RaceTrack.t(), map()) :: {:ok, RaceTrack.t()} | {:error, Ecto.Changeset.t()}
  def update(%RaceTrack{} = track, attrs) do
    track
    |> RaceTrack.changeset(attrs)
    |> Repo.update()
  end

  @spec delete(RaceTrack.t()) :: {:ok, RaceTrack.t()} | {:error, Ecto.Changeset.t()}
  def delete(%RaceTrack{} = track), do: Repo.delete(track)

  defp from_module(mod) do
    %{
      source: :code,
      slug: mod.slug(),
      name: mod.name(),
      model_path: mod.model_path(),
      thumbnail_path: nil,
      length_meters: mod.length_meters(),
      laps: mod.laps(),
      grid_size: mod.grid_size(),
      weather_bias: mod.weather_bias(),
      difficulty: 1
    }
  end

  defp from_db(%RaceTrack{} = t) do
    %{
      source: :db,
      slug: t.slug,
      name: t.name,
      model_path: t.track_model_path,
      thumbnail_path: t.thumbnail_path,
      length_meters: t.length_meters || 1000.0,
      laps: t.laps || 1,
      grid_size: t.grid_size || 24,
      weather_bias: atomize_weather_bias(t.weather_bias),
      difficulty: t.difficulty || 1
    }
  end

  defp atomize_weather_bias(nil), do: %{}

  defp atomize_weather_bias(map) when is_map(map) do
    for {k, v} <- map, is_number(v), into: %{} do
      key =
        case k do
          k when is_atom(k) ->
            k

          k when is_binary(k) ->
            try do
              String.to_existing_atom(k)
            rescue
              ArgumentError -> nil
            end
        end

      {key, v / 1}
    end
    |> Map.delete(nil)
  end
end
