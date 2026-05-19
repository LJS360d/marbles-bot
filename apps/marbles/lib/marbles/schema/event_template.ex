defmodule Marbles.Schema.EventTemplate do
  @moduledoc """
  Blueprint for a recurring event. Schedules point at templates; the
  CronScheduler clones an EventTemplate into a live `Marbles.Schema.Event`
  row at each cron tick.

  Templates carry no start/end_time — those are computed from
  `default_duration_seconds` + the schedule's `advance_seconds` at fire time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          banner_path: String.t() | nil,
          event_type: :scheduled_race | :tournament | :special_event | nil,
          config: map() | nil,
          default_duration_seconds: integer(),
          active: boolean(),
          schedules: Ecto.Association.NotLoaded.t() | [Marbles.Schema.EventSchedule.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "event_templates" do
    field :name, :string
    field :description, :string
    field :banner_path, :string

    field :event_type, Ecto.Enum,
      values: [:scheduled_race, :tournament, :special_event],
      default: :scheduled_race

    field :config, :map, default: %{}
    field :default_duration_seconds, :integer, default: 3600
    field :active, :boolean, default: true

    has_many :schedules, Marbles.Schema.EventSchedule, foreign_key: :template_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :name,
      :description,
      :banner_path,
      :event_type,
      :config,
      :default_duration_seconds,
      :active
    ])
    |> validate_required([:name, :event_type, :default_duration_seconds])
    |> validate_number(:default_duration_seconds, greater_than_or_equal_to: 60)
    |> validate_config()
  end

  defp validate_config(changeset) do
    config = get_field(changeset, :config) || %{}

    case get_field(changeset, :event_type) do
      :scheduled_race ->
        validate_race_config(changeset, config)

      _ ->
        changeset
    end
  end

  defp validate_race_config(changeset, config) do
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
