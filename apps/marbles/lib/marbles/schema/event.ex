defmodule Marbles.Schema.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "events" do
    field :name, :string
    field :description, :string
    field :start_time, :utc_datetime_usec
    field :end_time, :utc_datetime_usec
    field :banner_path, :string

    field :event_type, Ecto.Enum,
      values: [:scheduled_race, :tournament, :special_event],
      default: :scheduled_race

    field :config, :map, default: %{}
    field :active, :boolean, default: true

    has_many :registrations, Marbles.Schema.EventRegistration, foreign_key: :event_id

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :name,
      :description,
      :start_time,
      :end_time,
      :banner_path,
      :event_type,
      :config,
      :active
    ])
    |> validate_required([:name, :start_time, :end_time, :event_type])
    |> validate_datetime_order()
    |> validate_config()
  end

  defp validate_datetime_order(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && DateTime.compare(start_time, end_time) != :lt do
      add_error(changeset, :end_time, "must be after start time")
    else
      changeset
    end
  end

  defp validate_config(changeset) do
    config = get_field(changeset, :config) || %{}

    # Basic validation for config structure
    # Can be extended based on event_type
    case get_field(changeset, :event_type) do
      :scheduled_race ->
        validate_race_config(changeset, config)

      _ ->
        changeset
    end
  end

  defp validate_race_config(changeset, config) do
    # Validate required fields for race config
    required = ["track_id", "payout_multiplier", "grade"]
    missing = Enum.reject(required, &Map.has_key?(config, &1))

    if Enum.empty?(missing) do
      changeset
    else
      add_error(
        changeset,
        :config,
        "missing required fields for race: #{Enum.join(missing, ", ")}"
      )
    end
  end
end
