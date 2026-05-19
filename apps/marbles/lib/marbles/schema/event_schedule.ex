defmodule Marbles.Schema.EventSchedule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          template_id: Ecto.UUID.t() | nil,
          template: Ecto.Association.NotLoaded.t() | Marbles.Schema.EventTemplate.t(),
          cron_expr: String.t() | nil,
          next_run_at: DateTime.t() | nil,
          last_run_at: DateTime.t() | nil,
          active: boolean(),
          advance_seconds: integer(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "event_schedules" do
    belongs_to :template, Marbles.Schema.EventTemplate
    field :cron_expr, :string
    field :next_run_at, :utc_datetime_usec
    field :last_run_at, :utc_datetime_usec
    field :active, :boolean, default: true
    field :advance_seconds, :integer, default: 3600
    timestamps()
  end

  @doc """
  Changeset for user-supplied schedule attributes.
  `template_id`, `next_run_at`, and `last_run_at` are set programmatically
  by `Marbles.Racing.EventSchedules` — never cast from user input.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:cron_expr, :active, :advance_seconds])
    |> validate_required([:cron_expr])
    |> validate_cron_expr()
    |> validate_number(:advance_seconds, greater_than_or_equal_to: 60)
  end

  defp validate_cron_expr(changeset) do
    case get_field(changeset, :cron_expr) do
      nil ->
        changeset

      expr ->
        case Crontab.CronExpression.Parser.parse(expr) do
          {:ok, _} ->
            changeset

          {:error, _} ->
            add_error(changeset, :cron_expr, "invalid cron expression (e.g. \"0 20 * * *\")")
        end
    end
  end
end
