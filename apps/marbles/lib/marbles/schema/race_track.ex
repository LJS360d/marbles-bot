defmodule Marbles.Schema.RaceTrack do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          track_model_path: String.t() | nil,
          thumbnail_path: String.t() | nil,
          start_positions: map(),
          checkpoints: map(),
          finish_line: map(),
          length_meters: float(),
          laps: integer(),
          grid_size: integer(),
          weather_bias: map(),
          difficulty: integer(),
          max_players: integer(),
          active: boolean(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "race_tracks" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :track_model_path, :string
    field :thumbnail_path, :string
    field :start_positions, :map, default: %{}
    field :checkpoints, :map, default: %{}
    field :finish_line, :map, default: %{}
    field :length_meters, :float, default: 1000.0
    field :laps, :integer, default: 1
    field :grid_size, :integer, default: 24
    field :weather_bias, :map, default: %{}
    field :difficulty, :integer, default: 1
    field :max_players, :integer, default: 100
    field :active, :boolean, default: true

    timestamps()
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(race_track, attrs) do
    race_track
    |> cast(attrs, [
      :slug,
      :name,
      :description,
      :track_model_path,
      :thumbnail_path,
      :start_positions,
      :checkpoints,
      :finish_line,
      :length_meters,
      :laps,
      :grid_size,
      :weather_bias,
      :difficulty,
      :max_players,
      :active
    ])
    |> validate_required([:slug, :name])
    |> validate_number(:difficulty, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:max_players, greater_than: 0)
    |> validate_number(:length_meters, greater_than: 0.0)
    |> validate_number(:laps, greater_than: 0)
    |> validate_start_positions()
    |> validate_checkpoints()
    |> validate_finish_line()
    |> unique_constraint(:slug)
  end

  defp validate_start_positions(changeset) do
    start_positions = get_field(changeset, :start_positions) || %{}

    if is_map(start_positions) do
      changeset
    else
      add_error(changeset, :start_positions, "must be a map")
    end
  end

  defp validate_checkpoints(changeset) do
    checkpoints = get_field(changeset, :checkpoints) || %{}

    if is_map(checkpoints) do
      changeset
    else
      add_error(changeset, :checkpoints, "must be a map")
    end
  end

  defp validate_finish_line(changeset) do
    finish_line = get_field(changeset, :finish_line) || %{}

    cond do
      not is_map(finish_line) ->
        add_error(changeset, :finish_line, "must be a map")

      map_size(finish_line) == 0 ->
        changeset

      Map.has_key?(finish_line, "x") and Map.has_key?(finish_line, "z") ->
        changeset

      true ->
        add_error(changeset, :finish_line, "must be empty or contain 'x' and 'z'")
    end
  end
end
