defmodule MarblesWeb.Admin.OwnerSchedulesLive do
  @moduledoc "Owner-only index of recurring schedules."

  use MarblesWeb, :live_view

  alias Marbles.Racing.EventSchedules
  alias Marbles.Racing.Events.CronScheduler

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Schedules")
     |> assign(:current_scope, :owner_schedules)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Schedules", nil}])
     |> load_schedules()}
  end

  defp load_schedules(socket) do
    assign(socket, :schedules, EventSchedules.list_all())
  end

  @impl true
  def handle_event("fire_now", %{"id" => id}, socket) do
    with {:ok, schedule} <- EventSchedules.get_schedule(id),
         {:ok, event} <- CronScheduler.fire_now(schedule) do
      {:noreply,
       socket
       |> put_flash(:info, "Materialized event #{event.id} from schedule.")
       |> load_schedules()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not fire schedule.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, schedule} <- EventSchedules.get_schedule(id),
         {:ok, _} <- EventSchedules.delete_schedule(schedule) do
      {:noreply,
       socket
       |> put_flash(:info, "Schedule deleted.")
       |> load_schedules()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete schedule.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-5">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Schedules</h1>
          <.link
            navigate={~p"/admin/owner/schedules/new"}
            class="btn btn-primary btn-sm rounded-full"
          >
            <.icon name="hero-plus" class="size-4" /> New
          </.link>
        </header>

        <p class="text-sm text-base-content/60 max-w-prose">
          Each schedule materializes its template into a live event at the next cron tick.
          Manual fire bypasses the cron and runs immediately.
        </p>

        <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Template</th>
                <th>Cron</th>
                <th>Next run</th>
                <th>Last run</th>
                <th>Active</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={sched <- @schedules} id={"schedule-row-#{sched.id}"}>
                <td class="font-medium">
                  <.link
                    navigate={~p"/admin/owner/templates/#{sched.template_id}/edit"}
                    class="hover:underline"
                  >
                    {sched.template.name}
                  </.link>
                </td>
                <td class="font-mono text-xs">{sched.cron_expr}</td>
                <td class="text-xs text-base-content/60">{format_dt(sched.next_run_at)}</td>
                <td class="text-xs text-base-content/60">{format_dt(sched.last_run_at)}</td>
                <td>{if sched.active, do: "yes", else: "no"}</td>
                <td class="text-right space-x-2">
                  <button
                    type="button"
                    phx-click="fire_now"
                    phx-value-id={sched.id}
                    id={"fire-#{sched.id}"}
                    class="btn btn-warning btn-xs"
                    data-confirm="Materialize this template into a live event now?"
                  >
                    Fire now
                  </button>
                  <.link
                    navigate={~p"/admin/owner/schedules/#{sched.id}/edit"}
                    class="btn btn-ghost btn-xs"
                  >
                    Edit
                  </.link>
                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={sched.id}
                    data-confirm="Delete this schedule?"
                    id={"delete-#{sched.id}"}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </td>
              </tr>
              <tr :if={@schedules == []}>
                <td colspan="6" class="text-center text-base-content/60 py-6">
                  No schedules yet. Create a template first, then add a schedule.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_dt(nil), do: "—"
  defp format_dt(dt), do: Calendar.strftime(dt, "%b %d %H:%M UTC")
end
