defmodule Marbles.Racing.EventSchedules do
  @moduledoc """
  CRUD context for event_schedules — owner-configured recurring runs of an
  EventTemplate.

  Each schedule points at an `EventTemplate` (N:1). When `next_run_at` is
  reached, the CronScheduler materializes the template into a new live
  `Event` with adjusted times, then advances `next_run_at` to the
  following cron tick.
  """

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Schema.EventSchedule

  @type schedule_error :: :not_found

  @doc "Returns all schedules, preloaded with their template."
  @spec list_all() :: [EventSchedule.t()]
  def list_all do
    from(s in EventSchedule,
      preload: [:template],
      order_by: [asc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Returns schedules attached to the given template."
  @spec list_by_template(Ecto.UUID.t()) :: [EventSchedule.t()]
  def list_by_template(template_id) do
    from(s in EventSchedule,
      where: s.template_id == ^template_id,
      order_by: [asc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Fetches a schedule by id. Returns {:error, :not_found} if missing."
  @spec get_schedule(Ecto.UUID.t()) :: {:ok, EventSchedule.t()} | {:error, :not_found}
  def get_schedule(id) do
    case Repo.get(EventSchedule, id) do
      nil -> {:error, :not_found}
      s -> {:ok, Repo.preload(s, :template)}
    end
  end

  @doc """
  Creates a new schedule attached to the given template.
  Computes `next_run_at` from the cron expression immediately.
  """
  @spec create_for_template(Ecto.UUID.t(), map()) ::
          {:ok, EventSchedule.t()} | {:error, Ecto.Changeset.t()}
  def create_for_template(template_id, attrs) do
    %EventSchedule{}
    |> EventSchedule.changeset(attrs)
    |> Ecto.Changeset.put_change(:template_id, template_id)
    |> put_next_run(DateTime.utc_now())
    |> Repo.insert()
  end

  @doc "Updates schedule attributes and recomputes `next_run_at`."
  @spec update_schedule(EventSchedule.t(), map()) ::
          {:ok, EventSchedule.t()} | {:error, Ecto.Changeset.t()}
  def update_schedule(%EventSchedule{} = schedule, attrs) do
    schedule
    |> EventSchedule.changeset(attrs)
    |> put_next_run(DateTime.utc_now())
    |> Repo.update()
  end

  @doc "Deletes a schedule."
  @spec delete_schedule(EventSchedule.t()) ::
          {:ok, EventSchedule.t()} | {:error, Ecto.Changeset.t()}
  def delete_schedule(%EventSchedule{} = schedule) do
    Repo.delete(schedule)
  end

  @doc """
  Records a successful fire and advances `next_run_at` to the next cron tick
  after `fired_at`.
  """
  @spec mark_fired(EventSchedule.t(), DateTime.t()) ::
          {:ok, EventSchedule.t()} | {:error, Ecto.Changeset.t()}
  def mark_fired(%EventSchedule{} = schedule, fired_at) do
    schedule
    |> EventSchedule.changeset(%{})
    |> Ecto.Changeset.put_change(:last_run_at, fired_at)
    |> put_next_run(fired_at)
    |> Repo.update()
  end

  defp put_next_run(changeset, from_dt) do
    cron_expr = Ecto.Changeset.get_field(changeset, :cron_expr)

    case next_run_datetime(cron_expr, from_dt) do
      {:ok, next} -> Ecto.Changeset.put_change(changeset, :next_run_at, next)
      :error -> changeset
    end
  end

  defp next_run_datetime(nil, _from), do: :error

  defp next_run_datetime(cron_expr, from_dt) do
    with {:ok, parsed} <- Crontab.CronExpression.Parser.parse(cron_expr),
         naive_from <- DateTime.to_naive(from_dt),
         {:ok, naive_next} <- Crontab.Scheduler.get_next_run_date(parsed, naive_from),
         {:ok, next_run_at} <- DateTime.from_naive(naive_next, "Etc/UTC") do
      {:ok, next_run_at}
    else
      _ -> :error
    end
  end
end
