defmodule Marbles.Schema.RaceTrack do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "race_tracks" do
    field :name, :string
    field :description, :string
    field :track_model_path, :string
    field :thumbnail_path, :string
    field :start_positions, :map, default: %{}
    field :checkpoints, :map, default: %{}
    field :finish_line, :map, default: %{}
    field :difficulty, :integer, default: 1
    field :max_players, :integer, default: 100
    field :active, :boolean, default: true

    timestamps()
  end

  def changeset(race_track, attrs) do
    race_track
    |> cast(attrs, [
      :name,
      :description,
      :track_model_path,
      :thumbnail_path,
      :start_positions,
      :checkpoints,
      :finish_line,
      :difficulty,
      :max_players,
      :active
    ])
    |> validate_required([:name])
    |> validate_number(:difficulty, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:max_players, greater_than: 0)
    |> validate_start_positions()
    |> validate_checkpoints()
    |> validate_finish_line()
  end

  defp validate_start_positions(changeset) do
    start_positions = get_field(changeset, :start_positions) || %{}

    if is_map(start_positions) and map_size(start_positions) > 0 do
      changeset
    else
      add_error(changeset, :start_positions, "must be a non-empty map")
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

    if is_map(finish_line) and Map.has_key?(finish_line, "x") and Map.has_key?(finish_line, "z") do
      changeset
    else
      add_error(changeset, :finish_line, "must be a map with at least 'x' and 'z' keys")
    end
  end
end
