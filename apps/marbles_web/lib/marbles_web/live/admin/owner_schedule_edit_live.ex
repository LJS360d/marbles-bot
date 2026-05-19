defmodule MarblesWeb.Admin.OwnerScheduleEditLive do
  @moduledoc "Owner-only create / edit form for a recurring schedule."

  use MarblesWeb, :live_view

  alias Marbles.Racing.{EventSchedules, EventTemplates}
  alias Marbles.Schema.EventSchedule

  @impl true
  def mount(params, _session, socket) do
    {schedule, action} =
      case params do
        %{"id" => id} ->
          {:ok, sched} = EventSchedules.get_schedule(id)
          {sched, :edit}

        _ ->
          {%EventSchedule{advance_seconds: 3600, active: true}, :new}
      end

    templates = EventTemplates.list_active()

    selected_template_id =
      cond do
        action == :edit -> schedule.template_id
        templates != [] -> hd(templates).id
        true -> nil
      end

    {:ok,
     socket
     |> assign(:page_title, if(action == :new, do: "New schedule", else: "Edit schedule"))
     |> assign(:current_scope, :owner_schedules)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Schedules", ~p"/admin/owner/schedules"},
       {if(action == :new, do: "New", else: "Edit"), nil}
     ])
     |> assign(:action, action)
     |> assign(:schedule, schedule)
     |> assign(:templates, templates)
     |> assign(:selected_template_id, selected_template_id)
     |> assign_form()
     |> assign_preview()}
  end

  defp assign_form(socket) do
    cs = EventSchedule.changeset(socket.assigns.schedule, %{})
    assign(socket, :form, to_form(cs, as: :schedule))
  end

  defp assign_preview(socket) do
    cron = socket.assigns.schedule.cron_expr
    assign(socket, :preview, next_runs(cron, 5))
  end

  @impl true
  def handle_event("validate", %{"schedule" => attrs}, socket) do
    cs =
      socket.assigns.schedule
      |> EventSchedule.changeset(attrs)
      |> Map.put(:action, :validate)

    preview = next_runs(Ecto.Changeset.get_field(cs, :cron_expr), 5)

    {:noreply,
     socket
     |> assign(:form, to_form(cs, as: :schedule))
     |> assign(:preview, preview)
     |> assign(:selected_template_id, attrs["template_id"] || socket.assigns.selected_template_id)}
  end

  def handle_event("save", %{"schedule" => attrs}, socket) do
    template_id = attrs["template_id"] || socket.assigns.selected_template_id

    cond do
      template_id in [nil, ""] ->
        {:noreply, put_flash(socket, :error, "Select a template.")}

      socket.assigns.action == :new ->
        case EventSchedules.create_for_template(template_id, attrs) do
          {:ok, _sched} ->
            {:noreply,
             socket
             |> put_flash(:info, "Schedule created.")
             |> push_navigate(to: ~p"/admin/owner/schedules")}

          {:error, cs} ->
            {:noreply, assign(socket, :form, to_form(cs, as: :schedule))}
        end

      true ->
        case EventSchedules.update_schedule(socket.assigns.schedule, attrs) do
          {:ok, _sched} ->
            {:noreply,
             socket
             |> put_flash(:info, "Schedule updated.")
             |> push_navigate(to: ~p"/admin/owner/schedules")}

          {:error, cs} ->
            {:noreply, assign(socket, :form, to_form(cs, as: :schedule))}
        end
    end
  end

  defp next_runs(nil, _n), do: []
  defp next_runs("", _n), do: []

  defp next_runs(expr, n) do
    with {:ok, parsed} <- Crontab.CronExpression.Parser.parse(expr),
         naive_now <- DateTime.to_naive(DateTime.utc_now()) do
      parsed
      |> Crontab.Scheduler.get_next_run_dates(naive_now)
      |> Enum.take(n)
    else
      _ -> []
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
      <section class="max-w-3xl space-y-6">
        <h1 class="text-2xl font-bold">
          {if @action == :new, do: "New schedule", else: "Edit schedule"}
        </h1>

        <%= if @templates == [] do %>
          <div class="alert alert-warning">
            No active templates exist. Create one first at <.link
              navigate={~p"/admin/owner/templates/new"}
              class="underline"
            >
              Templates → New
            </.link>.
          </div>
        <% else %>
          <.form
            for={@form}
            id="schedule-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <div :if={@action == :new}>
              <label for="schedule_template_id" class="label-text text-sm font-medium block mb-1">
                Template
              </label>
              <select
                id="schedule_template_id"
                name="schedule[template_id]"
                class="select select-bordered w-full"
              >
                <%= for t <- @templates do %>
                  <option value={t.id} selected={t.id == @selected_template_id}>
                    {t.name} ({t.event_type})
                  </option>
                <% end %>
              </select>
            </div>

            <div :if={@action == :edit} class="text-sm">
              <span class="text-base-content/60">Template:</span>
              <.link
                navigate={~p"/admin/owner/templates/#{@schedule.template_id}/edit"}
                class="font-medium hover:underline"
              >
                {@schedule.template.name}
              </.link>
            </div>

            <.input field={@form[:cron_expr]} label="Cron expression" placeholder="0 20 * * *" />
            <p class="text-xs text-base-content/50 -mt-2">
              5-part cron: minute hour dom month dow. Example: <code>0 20 * * *</code>
              = every day at 20:00 UTC.
            </p>

            <.input
              field={@form[:advance_seconds]}
              type="number"
              label="Advance seconds"
            />
            <p class="text-xs text-base-content/50 -mt-2">
              How far in the future to set the new event's start_time when materialized.
            </p>

            <.input field={@form[:active]} type="checkbox" label="Active" />

            <div :if={@preview != []} class="rounded-xl border border-base-300 bg-base-200/50 p-3">
              <p class="text-xs font-medium text-base-content/70 mb-2">Next 5 runs (UTC)</p>
              <ul class="space-y-0.5 text-xs font-mono text-base-content/80">
                <%= for run <- @preview do %>
                  <li>{Calendar.strftime(run, "%b %d %Y %H:%M")}</li>
                <% end %>
              </ul>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" id="schedule-save" class="btn btn-primary btn-sm rounded-full">
                Save
              </button>
              <.link navigate={~p"/admin/owner/schedules"} class="btn btn-ghost btn-sm">
                Cancel
              </.link>
            </div>
          </.form>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
