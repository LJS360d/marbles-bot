defmodule MarblesWeb.CalendarLive do
  @moduledoc """
  Public events calendar. Two columns: upcoming and recently finished.
  """

  use MarblesWeb, :live_view

  alias Marbles.Racing.Events
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(Marbles.PubSub, Events.Runner.public_topic())

    upcoming = Events.list_upcoming(20)

    {:ok,
     socket
     |> assign(:page_title, "Calendar")
     |> assign(:current_scope, :calendar)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Calendar", nil}])
     |> assign(:upcoming, upcoming)}
  end

  @impl true
  def handle_info({:event_started, _id}, socket),
    do: {:noreply, assign(socket, :upcoming, Events.list_upcoming(20))}

  def handle_info({:event_finished, _id}, socket),
    do: {:noreply, assign(socket, :upcoming, Events.list_upcoming(20))}

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      race_state={@race_state}
      current_scope={:calendar}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-5">
        <header>
          <h1 class="text-3xl font-bold">Calendar</h1>
          <p class="text-sm text-base-content/70">Scheduled events. Sign up, race, win.</p>
        </header>

        <%= if @upcoming == [] do %>
          <div class="rounded-3xl border border-dashed border-base-300 bg-base-100/40 p-10 text-center text-base-content/60">
            <.icon name="hero-calendar-days" class="size-12 mx-auto opacity-50" />
            <p class="mt-3">No events scheduled. Check back later.</p>
          </div>
        <% else %>
          <div class="grid gap-5 md:grid-cols-2 lg:grid-cols-3">
            <article
              :for={event <- @upcoming}
              id={"event-#{event.id}"}
              class="rounded-3xl border border-base-300 bg-base-100/60 p-5 backdrop-blur"
            >
              <h3 class="text-lg font-semibold">{event.name}</h3>
              <p class="mt-1 text-xs text-base-content/60">
                {Calendar.strftime(event.start_time, "%a %b %d · %H:%M UTC")} → {Calendar.strftime(
                  event.end_time,
                  "%H:%M UTC"
                )}
              </p>
              <p :if={event.description} class="mt-3 line-clamp-3 text-sm text-base-content/80">
                {event.description}
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <span
                  :if={fee = Map.get(event.config || %{}, "entry_fee_coins")}
                  class="badge badge-outline"
                >
                  Fee: {fee}
                </span>
                <span
                  :if={mult = Map.get(event.config || %{}, "payout_multiplier")}
                  class="badge badge-outline"
                >
                  x{mult}
                </span>
              </div>
              <div class="mt-4">
                <.link navigate={~p"/events/#{event.id}"} class="btn btn-primary btn-sm rounded-full">
                  Open <.icon name="hero-arrow-right" class="size-4" />
                </.link>
              </div>
            </article>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
