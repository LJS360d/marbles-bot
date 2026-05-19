defmodule MarblesWeb.Admin.OwnerEventsLive do
  @moduledoc "Owner-only listing of scheduled events with schedule and calendar views."

  use MarblesWeb, :live_view

  alias Marbles.Racing.Events

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now()

    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:current_scope, :owner_events)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Events", nil}])
     |> assign(:events, Events.list_for_admin())
     |> assign(:active_tab, :events)
     |> assign(:cal_year, now.year)
     |> assign(:cal_month, now.month)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("start_now", %{"id" => id}, socket) do
    case Marbles.Racing.start_event!(id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Event run started.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start: #{inspect(reason)}")}
    end
  end

  def handle_event("cal_prev", _params, socket) do
    {year, month} = prev_month(socket.assigns.cal_year, socket.assigns.cal_month)
    {:noreply, socket |> assign(:cal_year, year) |> assign(:cal_month, month)}
  end

  def handle_event("cal_next", _params, socket) do
    {year, month} = next_month(socket.assigns.cal_year, socket.assigns.cal_month)
    {:noreply, socket |> assign(:cal_year, year) |> assign(:cal_month, month)}
  end

  @impl true
  def render(assigns) do
    cal_weeks = calendar_weeks(assigns.cal_year, assigns.cal_month, assigns.events)
    assigns = Map.put(assigns, :cal_weeks, cal_weeks)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={:owner_events}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-5">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Events</h1>
          <.link
            navigate={~p"/admin/owner/events/new"}
            class="btn btn-primary btn-sm rounded-full"
          >
            <.icon name="hero-plus" class="size-4" /> New
          </.link>
        </header>

        <%!-- Tab bar --%>
        <div class="tabs tabs-boxed w-fit" role="tablist">
          <button
            id="tab-events"
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="events"
            class={["tab", @active_tab == :events && "tab-active"]}
          >
            Events
          </button>
          <button
            id="tab-calendar"
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="calendar"
            class={["tab", @active_tab == :calendar && "tab-active"]}
          >
            Calendar
          </button>
        </div>

        <%!-- Events tab --%>
        <div :if={@active_tab == :events} id="tab-panel-events">
          <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Window</th>
                  <th>Type</th>
                  <th>Active</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={event <- @events} id={"event-row-#{event.id}"}>
                  <td>{event.name}</td>
                  <td class="text-xs text-base-content/60">
                    {Calendar.strftime(event.start_time, "%b %d %H:%M")} → {Calendar.strftime(
                      event.end_time,
                      "%H:%M"
                    )}
                  </td>
                  <td>{event.event_type}</td>
                  <td>{if event.active, do: "yes", else: "no"}</td>
                  <td class="text-right space-x-2">
                    <.link
                      navigate={~p"/admin/owner/events/#{event.id}/edit"}
                      class="btn btn-ghost btn-xs"
                    >
                      Edit
                    </.link>
                    <button
                      type="button"
                      phx-click="start_now"
                      phx-value-id={event.id}
                      id={"start-#{event.id}"}
                      class="btn btn-warning btn-xs"
                    >
                      Start now
                    </button>
                  </td>
                </tr>
                <tr :if={@events == []}>
                  <td colspan="5" class="text-center text-base-content/60 py-6">
                    No events yet.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Calendar tab --%>
        <div :if={@active_tab == :calendar} id="tab-panel-calendar">
          <div class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-3">
            <%!-- Month navigation --%>
            <div class="flex items-center justify-between">
              <button
                id="cal-prev"
                type="button"
                phx-click="cal_prev"
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </button>
              <span class="font-semibold text-sm">
                {month_name(@cal_month)} {@cal_year}
              </span>
              <button
                id="cal-next"
                type="button"
                phx-click="cal_next"
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-chevron-right" class="size-4" />
              </button>
            </div>

            <%!-- Day-of-week header --%>
            <div class="grid grid-cols-7 text-center text-xs font-medium text-base-content/50 pb-1 border-b border-base-300">
              <span>Sun</span>
              <span>Mon</span>
              <span>Tue</span>
              <span>Wed</span>
              <span>Thu</span>
              <span>Fri</span>
              <span>Sat</span>
            </div>

            <%!-- Weeks --%>
            <div id="cal-grid" class="space-y-1">
              <%= for week <- @cal_weeks do %>
                <div class="grid grid-cols-7 gap-1">
                  <%= for {day, day_events} <- week do %>
                    <div class={[
                      "min-h-[4rem] rounded-xl p-1 text-xs",
                      day && "bg-base-200/50",
                      !day && "opacity-0 pointer-events-none"
                    ]}>
                      <%= if day do %>
                        <span class="font-medium text-base-content/60 block mb-0.5">
                          {day.day}
                        </span>
                        <div class="space-y-0.5">
                          <%= for ev <- day_events do %>
                            <.link
                              navigate={~p"/admin/owner/events/#{ev.id}/edit"}
                              class="block truncate rounded px-1 py-0.5 bg-primary/20 text-primary hover:bg-primary/30 transition-colors"
                              id={"cal-ev-#{ev.id}-#{day}"}
                            >
                              {ev.name}
                            </.link>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # --- helpers ---

  defp month_name(m) do
    ~w(January February March April May June July August September October November December)
    |> Enum.at(m - 1)
  end

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}

  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp calendar_weeks(year, month, events) do
    {:ok, first_day} = Date.new(year, month, 1)
    days_in_month = Date.days_in_month(first_day)

    # ISO day_of_week: 1=Mon..7=Sun. Convert to Sunday-first (0=Sun).
    first_dow =
      case Date.day_of_week(first_day, :monday) do
        7 -> 0
        n -> n
      end

    all_days = Enum.map(1..days_in_month, &Date.new!(year, month, &1))

    # Map date -> events starting on that date
    events_by_date =
      Enum.group_by(events, fn ev ->
        DateTime.to_date(ev.start_time)
      end)

    cells =
      List.duplicate(nil, first_dow) ++
        Enum.map(all_days, fn d -> {d, Map.get(events_by_date, d, [])} end)

    pad = rem(length(cells), 7)
    cells = if pad == 0, do: cells, else: cells ++ List.duplicate(nil, 7 - pad)

    Enum.chunk_every(cells, 7)
  end
end
