defmodule MarblesWeb.Admin.OwnerEventsLive do
  @moduledoc "Owner-only listing of scheduled events."

  use MarblesWeb, :live_view

  alias Marbles.Racing.Events

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:current_scope, :owner_events)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Events", nil}])
     |> assign(:events, Events.list_for_admin())}
  end

  @impl true
  def handle_event("start_now", %{"id" => id}, socket) do
    case Marbles.Racing.start_event!(id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Event run started.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
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
      </section>
    </Layouts.app>
    """
  end
end
