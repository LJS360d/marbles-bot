defmodule Marbles.Racing.Events.CronScheduler do
  @moduledoc """
  Ticks every minute. Materializes due event_schedules into live Event rows
  by cloning the schedule's EventTemplate with computed start/end times.

  This is distinct from `Marbles.Racing.Events.Scheduler`, which launches
  already-created events that have reached their `start_time`.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Racing.{Events, EventSchedules}
  alias Marbles.Schema.EventSchedule

  @tick_ms 60_000

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  @spec init(:ok) :: {:ok, nil}
  def init(:ok) do
    schedule_tick()
    {:ok, nil}
  end

  @impl true
  @spec handle_info(:tick | term(), nil) :: {:noreply, nil}
  def handle_info(:tick, state) do
    fire_due()
    schedule_tick()
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @doc """
  Force-materializes a single schedule into a live Event immediately.
  Used by the admin schedules page's manual-fire button.
  """
  @spec fire_now(EventSchedule.t()) ::
          {:ok, Marbles.Schema.Event.t()} | {:error, term()}
  def fire_now(%EventSchedule{} = schedule) do
    schedule = Repo.preload(schedule, :template)
    fire_schedule(schedule, DateTime.utc_now())
  end

  defp fire_due do
    now = DateTime.utc_now()

    from(s in EventSchedule,
      where: s.active == true and not is_nil(s.next_run_at) and s.next_run_at <= ^now,
      preload: [:template]
    )
    |> Repo.all()
    |> Enum.each(&fire_schedule(&1, now))
  end

  defp fire_schedule(%EventSchedule{template: template} = schedule, now) do
    advance = schedule.advance_seconds
    start_time = DateTime.add(now, advance, :second)
    duration_s = template.default_duration_seconds
    end_time = DateTime.add(start_time, duration_s, :second)

    attrs = %{
      "name" => template.name,
      "description" => template.description,
      "banner_path" => template.banner_path,
      "event_type" => to_string(template.event_type),
      "config" => template.config,
      "active" => true,
      "start_time" => start_time,
      "end_time" => end_time,
      "template_id" => template.id
    }

    case Events.create_event(attrs) do
      {:ok, event} ->
        Logger.info("CronScheduler: materialized event #{event.id} from schedule #{schedule.id}")
        EventSchedules.mark_fired(schedule, now)
        {:ok, event}

      {:error, reason} = err ->
        Logger.error(
          "CronScheduler: failed to materialize schedule #{schedule.id}: #{inspect(reason)}"
        )

        err
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)
end
