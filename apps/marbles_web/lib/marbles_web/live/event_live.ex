defmodule MarblesWeb.EventLive do
  @moduledoc """
  Public event detail. Lets logged-in users sign up with one of their squads.
  """

  use MarblesWeb, :live_view

  alias Marbles.Racing.{Events, Squads}
  alias Marbles.Schema.EventRegistration

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Events.get_event(id) do
      {:ok, event} ->
        squads =
          if socket.assigns[:current_user],
            do: Squads.list_user_squads(socket.assigns.current_user.id),
            else: []

        already? =
          if socket.assigns[:current_user] do
            !!Marbles.Repo.get_by(EventRegistration,
              event_id: event.id,
              user_id: socket.assigns.current_user.id
            )
          else
            false
          end

        {:ok,
         socket
         |> assign(:page_title, event.name)
         |> assign(:current_scope, :event)
         |> assign(:show_login_modal, false)
         |> assign(:event, event)
         |> assign(:squads, squads)
         |> assign(:selected_squad_id, default_squad_id(squads))
         |> assign(:already_registered?, already?)
         |> assign(:breadcrumbs, [{"Calendar", ~p"/calendar"}, {event.name, nil}])}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Event not found") |> redirect(to: ~p"/calendar")}
    end
  end

  @impl true
  def handle_event("select_squad", %{"squad_id" => id}, socket),
    do: {:noreply, assign(socket, :selected_squad_id, id)}

  def handle_event("register", _params, socket) do
    if socket.assigns[:current_user] == nil do
      {:noreply, redirect(socket, to: ~p"/login")}
    else
      case Events.register(
             socket.assigns.event.id,
             socket.assigns.current_user.id,
             socket.assigns.selected_squad_id
           ) do
        {:ok, _reg} ->
          {:noreply,
           socket
           |> put_flash(:info, "Signed up.")
           |> assign(:already_registered?, true)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason_message(reason))}
      end
    end
  end

  defp default_squad_id([]), do: nil
  defp default_squad_id([first | _]), do: first.id

  defp reason_message(:event_closed), do: "Sign-ups are closed."
  defp reason_message(:already_registered), do: "You're already registered."
  defp reason_message(:insufficient_funds), do: "Not enough coins."
  defp reason_message(:ineligible), do: "Your squad doesn't meet event rules."
  defp reason_message(:invalid_squad), do: "That squad is invalid."
  defp reason_message(other), do: "Could not register: #{inspect(other)}."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={:event}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="grid gap-6 lg:grid-cols-3">
        <article class="lg:col-span-2 rounded-3xl border border-base-300 bg-base-100/60 p-6 backdrop-blur space-y-3">
          <h1 class="text-3xl font-bold">{@event.name}</h1>
          <p class="text-sm text-base-content/60">
            {Calendar.strftime(@event.start_time, "%a %b %d · %H:%M UTC")} → {Calendar.strftime(
              @event.end_time,
              "%H:%M UTC"
            )}
          </p>
          <p :if={@event.description} class="text-base-content/80">{@event.description}</p>

          <div class="mt-4 flex flex-wrap gap-2">
            <span
              :for={{label, value} <- rule_chips(@event.config || %{})}
              class="badge badge-outline"
            >
              {label}: {value}
            </span>
          </div>
        </article>

        <aside class="rounded-3xl border border-base-300 bg-base-100/60 p-6 backdrop-blur space-y-3">
          <h2 class="text-lg font-semibold">Sign up</h2>
          <%= cond do %>
            <% @current_user == nil -> %>
              <p class="text-sm text-base-content/70">Log in to sign up.</p>
              <.link href={~p"/login"} class="btn btn-primary btn-sm rounded-full">
                Log in
              </.link>
            <% @already_registered? -> %>
              <p class="text-sm text-base-content/70">You're signed up. See you on the start grid.</p>
            <% @squads == [] -> %>
              <p class="text-sm text-base-content/70">You need a squad first.</p>
              <.link navigate={~p"/roster"} class="btn btn-primary btn-sm rounded-full">
                Build a squad
              </.link>
            <% true -> %>
              <ul class="space-y-2">
                <li :for={squad <- @squads}>
                  <button
                    type="button"
                    phx-click="select_squad"
                    phx-value-squad_id={squad.id}
                    id={"event-squad-#{squad.id}"}
                    class={[
                      "w-full rounded-2xl border px-3 py-2 text-left text-sm transition",
                      @selected_squad_id == squad.id && "border-primary bg-primary/10",
                      @selected_squad_id != squad.id && "border-base-300 hover:bg-base-200/40"
                    ]}
                  >
                    {squad.name}
                  </button>
                </li>
              </ul>
              <button
                type="button"
                phx-click="register"
                id="event-register"
                class="btn btn-primary btn-sm rounded-full w-full"
              >
                Sign up · {Map.get(@event.config || %{}, "entry_fee_coins", 0)} coins
              </button>
          <% end %>
        </aside>
      </section>
    </Layouts.app>
    """
  end

  defp rule_chips(cfg) do
    [
      {"Fee", Map.get(cfg, "entry_fee_coins", 0)},
      {"Pool", Map.get(cfg, "pool_size", 8)},
      {"Payout", "x#{Map.get(cfg, "payout_multiplier", 1.0)}"},
      {"ELO", "#{Map.get(cfg, "elo_min", 0)}–#{Map.get(cfg, "elo_max", 5_000)}"},
      {"Min level", Map.get(cfg, "min_marble_level", 1)}
    ]
  end
end
