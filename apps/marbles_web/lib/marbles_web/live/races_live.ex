defmodule MarblesWeb.RacesLive do
  @moduledoc "Public hub for quick races and scheduled events."

  use MarblesWeb, :live_view

  alias Marbles.Racing.{Events, Queue}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Marbles.PubSub, Queue.public_topic())
    end

    {:ok,
     socket
     |> assign(:page_title, "Races")
     |> assign(:current_scope, :race)
     |> assign(:show_login_modal, false)
     |> load_state()}
  end

  defp load_state(socket) do
    socket
    |> assign(:queue_stats, Queue.stats())
    |> assign(:upcoming, Events.list_upcoming(5))
  end

  @impl true
  def handle_info({:queue_stats, stats}, socket),
    do: {:noreply, assign(socket, :queue_stats, stats)}

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      race_state={@race_state}
      current_user={@current_user}
      current_scope={@current_scope}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-6 py-4">
        <h1 class="text-3xl font-bold">Races</h1>

        <%!-- Quick join --%>
        <div class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-5 space-y-3">
          <h2 class="text-lg font-semibold">Quick race</h2>
          <p class="text-sm text-base-content/70">
            {@queue_stats.total} player(s) queued across {map_size(@queue_stats.brackets)} bracket(s).
          </p>
          <p class="text-xs text-base-content/50">
            Join via Discord <code>/race queue</code> for now — web-side quick join landing soon.
          </p>
        </div>

        <%!-- Upcoming events --%>
        <div class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-5 space-y-3">
          <h2 class="text-lg font-semibold">Upcoming events</h2>
          <ul :if={@upcoming != []} class="divide-y divide-base-300">
            <li :for={ev <- @upcoming} class="py-2 flex items-center justify-between">
              <div>
                <p class="font-medium">{ev.name}</p>
                <p class="text-xs text-base-content/60">
                  {Calendar.strftime(ev.start_time, "%b %d %H:%M UTC")}
                </p>
              </div>
              <.link
                navigate={~p"/events/#{ev.id}"}
                class="btn btn-ghost btn-sm"
              >
                Open
              </.link>
            </li>
          </ul>
          <p :if={@upcoming == []} class="text-sm text-base-content/60">
            No upcoming events.
          </p>
        </div>

        <%!-- Sub-page links --%>
        <div class="grid gap-3 sm:grid-cols-2">
          <.link
            navigate={~p"/races/calendar"}
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 hover:bg-base-200 transition-colors"
          >
            <p class="font-semibold">Calendar</p>
            <p class="text-xs text-base-content/60">Month grid of upcoming events</p>
          </.link>
          <.link
            navigate={~p"/"}
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 hover:bg-base-200 transition-colors opacity-60"
          >
            <p class="font-semibold">Replays</p>
            <p class="text-xs text-base-content/60">Coming soon</p>
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
