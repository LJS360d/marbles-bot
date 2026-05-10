defmodule MarblesWeb.HomeLive do
  @moduledoc """
  Redesigned landing page. Gacha-game feel: minimal copy, two large
  primary CTAs (Quick Race, Calendar), live queue strip, featured event,
  featured pack.
  """

  use MarblesWeb, :live_view

  alias Marbles.Packs
  alias Marbles.Racing
  alias Marbles.Racing.{Events, Queue}
  alias Marbles.Schema.UserRaceStat
  alias Phoenix.PubSub

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(Marbles.PubSub, Queue.public_topic())
      PubSub.subscribe(Marbles.PubSub, Events.Runner.public_topic())
    end

    {:ok,
     socket
     |> assign(:page_title, "Marbles")
     |> assign(:current_scope, nil)
     |> assign(:show_login_modal, false)
     |> assign(:queue_stats, Racing.queue_stats())
     |> assign(:featured_event, fetch_featured_event())
     |> assign(:featured_pack, fetch_featured_pack())
     |> assign(:user_elo, fetch_user_elo(socket.assigns[:current_user]))}
  end

  @impl true
  def handle_info({:queue_stats, stats}, socket),
    do: {:noreply, assign(socket, :queue_stats, stats)}

  def handle_info({:event_started, _id}, socket),
    do: {:noreply, assign(socket, :featured_event, fetch_featured_event())}

  def handle_info({:event_finished, _id}, socket),
    do: {:noreply, assign(socket, :featured_event, fetch_featured_event())}

  def handle_info(_other, socket), do: {:noreply, socket}

  defp fetch_featured_event do
    case Events.list_upcoming(1) do
      [event | _] -> event
      _ -> nil
    end
  end

  defp fetch_featured_pack do
    case Packs.list_active_packs() do
      [pack | _] -> pack
      _ -> nil
    end
  end

  defp fetch_user_elo(nil), do: nil

  defp fetch_user_elo(user) do
    case Marbles.Repo.get_by(UserRaceStat, user_id: user.id) do
      %UserRaceStat{elo: elo} -> elo
      nil -> 1000
    end
  end

  defp user_bracket(nil, _step), do: nil
  defp user_bracket(elo, step), do: div(elo, step)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={nil} show_login_modal={@show_login_modal}>
      <div id="home-page" class="relative isolate min-h-svh">
        <div
          aria-hidden="true"
          class="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(80rem_40rem_at_50%_-20%,oklch(72%_0.18_280/0.35),transparent),radial-gradient(60rem_40rem_at_120%_50%,oklch(75%_0.15_30/0.25),transparent)]"
        />

        <section class="mx-auto flex max-w-7xl flex-col gap-10 px-4 py-10 sm:py-14 md:px-8">
          <header class="flex flex-col items-center gap-5 text-center sm:gap-7">
            <div class="flex items-center gap-3">
              <span class="size-3 rounded-full bg-primary/80 animate-pulse" />
              <span class="text-xs uppercase tracking-[0.4em] text-base-content/60">
                Marbles · Season 1
              </span>
              <span class="size-3 rounded-full bg-secondary/80 animate-pulse" />
            </div>
          </header>

          <div class="grid gap-6 md:grid-cols-2">
            <.cta_button
              click={
                if @current_user,
                  do: Phoenix.LiveView.JS.dispatch("phx:race-dock:open"),
                  else: Phoenix.LiveView.JS.navigate(~p"/login")
              }
              kind="primary"
              icon="hero-bolt"
              title="Quick Race"
              tagline="Matchmade · ELO bracketed · 4–8 players"
            />
            <.cta_card
              href={~p"/calendar"}
              kind="secondary"
              icon="hero-calendar"
              title="Calendar"
              tagline="Scheduled events · big payouts"
            />
          </div>

          <.queue_strip
            stats={@queue_stats}
            user_bracket={user_bracket(@user_elo, @queue_stats.bracket_step)}
          />

          <div class="grid gap-6 lg:grid-cols-3">
            <div class="lg:col-span-2">
              <.featured_event_card event={@featured_event} />
            </div>
            <div>
              <.featured_pack_card pack={@featured_pack} current_user={@current_user} />
            </div>
          </div>

          <nav class="flex flex-wrap justify-center gap-3 pt-4">
            <.link navigate={~p"/roster"} class="btn btn-ghost btn-sm rounded-full">
              <.icon name="hero-user-group" class="size-4" /> Roster
            </.link>
            <.link navigate={~p"/gacha"} class="btn btn-ghost btn-sm rounded-full">
              <.icon name="hero-gift" class="size-4" /> Gacha
            </.link>
            <.link navigate={~p"/calendar"} class="btn btn-ghost btn-sm rounded-full">
              <.icon name="hero-calendar" class="size-4" /> Calendar
            </.link>
          </nav>

          <footer class="pt-6 text-center text-xs text-base-content/50">
            <nav class="inline-flex flex-wrap justify-center gap-x-3 gap-y-1" aria-label="Legal">
              <.link navigate={~p"/privacy-policy"} class="hover:underline">Privacy Policy</.link>
              <span aria-hidden="true">·</span>
              <.link navigate={~p"/terms-of-service"} class="hover:underline">
                Terms of Service
              </.link>
            </nav>
          </footer>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :href, :string, required: true
  attr :kind, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :tagline, :string, required: true

  defp cta_card(assigns) do
    ~H"""
    <.link
      href={@href}
      class={[
        "group relative flex flex-col gap-3 overflow-hidden rounded-3xl border p-8 transition-transform hover:-translate-y-0.5",
        @kind == "primary" &&
          "bg-linear-to-br from-primary/30 via-primary/15 to-transparent border-primary/40",
        @kind == "secondary" &&
          "bg-linear-to-br from-secondary/30 via-secondary/15 to-transparent border-secondary/40"
      ]}
    >
      <div class="absolute right-0 top-0 size-32 -translate-y-12 translate-x-12 rounded-full bg-white/10 blur-3xl transition-transform group-hover:translate-x-8 group-hover:-translate-y-8" />
      <div class="flex items-center gap-3 text-3xl font-bold tracking-tight">
        <.icon name={@icon} class="size-8" />
        {@title}
      </div>
      <p class="text-sm text-base-content/80">{@tagline}</p>
      <div class="mt-4 flex items-center gap-2 text-sm font-medium opacity-80 transition-opacity group-hover:opacity-100">
        Enter <.icon name="hero-arrow-right" class="size-4" />
      </div>
    </.link>
    """
  end

  attr :click, :any, required: true
  attr :kind, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :tagline, :string, required: true

  defp cta_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@click}
      class={[
        "group relative flex flex-col gap-3 overflow-hidden rounded-3xl border p-8 text-left transition-transform hover:-translate-y-0.5",
        @kind == "primary" &&
          "bg-linear-to-br from-primary/30 via-primary/15 to-transparent border-primary/40",
        @kind == "secondary" &&
          "bg-linear-to-br from-secondary/30 via-secondary/15 to-transparent border-secondary/40"
      ]}
    >
      <div class="absolute right-0 top-0 size-32 -translate-y-12 translate-x-12 rounded-full bg-white/10 blur-3xl transition-transform group-hover:translate-x-8 group-hover:-translate-y-8" />
      <div class="flex items-center gap-3 text-3xl font-bold tracking-tight">
        <.icon name={@icon} class="size-8" />
        {@title}
      </div>
      <p class="text-sm text-base-content/80">{@tagline}</p>
      <div class="mt-4 flex items-center gap-2 text-sm font-medium opacity-80 transition-opacity group-hover:opacity-100">
        Open dock <.icon name="hero-arrow-right" class="size-4" />
      </div>
    </button>
    """
  end

  attr :stats, :map, required: true
  attr :user_bracket, :any, default: nil

  defp queue_strip(assigns) do
    ~H"""
    <section
      id="queue-strip"
      class="overflow-hidden rounded-3xl border border-base-300 bg-base-100/60 p-5 backdrop-blur"
    >
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="text-xs uppercase tracking-[0.3em] text-base-content/60">Live queue</p>
          <p class="text-3xl font-black">
            {@stats.total} <span class="text-sm font-normal text-base-content/60">in queue</span>
          </p>
        </div>
        <button
          type="button"
          phx-click={Phoenix.LiveView.JS.dispatch("phx:race-dock:open")}
          class="btn btn-sm btn-primary rounded-full"
        >
          Open queue <.icon name="hero-arrow-right" class="size-4" />
        </button>
      </div>
      <div class="mt-4 flex flex-wrap gap-2">
        <%= if map_size(@stats.brackets) == 0 do %>
          <span class="text-sm text-base-content/60">No players in queue. Be the first.</span>
        <% else %>
          <%= for {bracket, count} <- Enum.sort_by(@stats.brackets, &elem(&1, 0)) do %>
            <.bracket_chip
              bracket={bracket}
              count={count}
              step={@stats.bracket_step}
              highlight={@user_bracket == bracket}
            />
          <% end %>
        <% end %>
      </div>
    </section>
    """
  end

  attr :bracket, :integer, required: true
  attr :count, :integer, required: true
  attr :step, :integer, required: true
  attr :highlight, :boolean, default: false

  defp bracket_chip(assigns) do
    assigns =
      assign(
        assigns,
        :range,
        "#{assigns.bracket * assigns.step}–#{(assigns.bracket + 1) * assigns.step - 1}"
      )

    ~H"""
    <div class={[
      "rounded-full border px-3 py-1 text-xs",
      @highlight && "border-primary bg-primary/20 text-primary-content",
      not @highlight && "border-base-300"
    ]}>
      <span class="font-mono">ELO {@range}</span>
      <span class="ml-2 font-semibold">{@count}</span>
    </div>
    """
  end

  attr :event, :any, required: true

  defp featured_event_card(%{event: nil} = assigns) do
    ~H"""
    <section class="rounded-3xl border border-dashed border-base-300 bg-base-100/40 p-8 text-center text-base-content/60">
      <.icon name="hero-calendar-days" class="size-10 mx-auto opacity-50" />
      <p class="mt-2">No upcoming events scheduled.</p>
    </section>
    """
  end

  defp featured_event_card(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-300 bg-base-100/60 p-6 backdrop-blur">
      <p class="text-xs uppercase tracking-[0.3em] text-base-content/60">Next event</p>
      <h2 class="mt-2 text-2xl font-bold">{@event.name}</h2>
      <p class="mt-2 text-sm text-base-content/70">
        {Calendar.strftime(@event.start_time, "%a %b %d · %H:%M UTC")} → {Calendar.strftime(
          @event.end_time,
          "%H:%M UTC"
        )}
      </p>
      <div class="mt-4 flex flex-wrap gap-2">
        <span :if={fee = Map.get(@event.config || %{}, "entry_fee_coins")} class="badge badge-outline">
          Fee: {fee} coins
        </span>
        <span
          :if={mult = Map.get(@event.config || %{}, "payout_multiplier")}
          class="badge badge-outline"
        >
          Payout x{mult}
        </span>
        <span :if={pool = Map.get(@event.config || %{}, "pool_size")} class="badge badge-outline">
          Pools of {pool}
        </span>
      </div>
      <div class="mt-5">
        <.link navigate={~p"/events/#{@event.id}"} class="btn btn-primary btn-sm rounded-full">
          Details <.icon name="hero-arrow-right" class="size-4" />
        </.link>
      </div>
    </section>
    """
  end

  attr :pack, :any, required: true
  attr :current_user, :any, default: nil

  defp featured_pack_card(%{pack: nil} = assigns) do
    ~H"""
    <section class="rounded-3xl border border-dashed border-base-300 bg-base-100/40 p-6 text-center text-base-content/60">
      <.icon name="hero-gift" class="size-10 mx-auto opacity-50" />
      <p class="mt-2 text-sm">No active packs.</p>
    </section>
    """
  end

  defp featured_pack_card(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-300 bg-base-100/60 p-6 backdrop-blur">
      <p class="text-xs uppercase tracking-[0.3em] text-base-content/60">Featured pack</p>
      <h3 class="mt-2 text-xl font-semibold">{@pack.name}</h3>
      <p :if={@pack.description} class="mt-2 line-clamp-3 text-sm text-base-content/70">
        {@pack.description}
      </p>
      <.link
        href={if @current_user, do: ~p"/gacha", else: ~p"/login"}
        class="btn btn-secondary btn-sm rounded-full mt-4"
      >
        Pull <.icon name="hero-arrow-right" class="size-4" />
      </.link>
    </section>
    """
  end
end
