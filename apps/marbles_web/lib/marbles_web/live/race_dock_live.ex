defmodule MarblesWeb.RaceDockLive do
  @moduledoc """
  Floating, draggable, resizable race dock embedded in the root layout via
  `live_render/3`. Because it lives in the root layout (which is sticky
  across `live_navigate`/`live_patch`), the dock LV process persists across
  page navigations within the same dead-view scope.

  The dock is a single source of truth for the user's queue / in-race
  state. It subscribes to:

    * `Marbles.Racing.Queue.public_topic/0` — queue stats broadcast.
    * `Marbles.Racing.Queue.user_topic/1`   — per-user queue lifecycle.
    * `Marbles.Racing.Engine.topic/1`       — race-specific frames + pot.

  States: `:idle`, `:queued`, `:in_race`.
  """

  use MarblesWeb, :live_view

  alias Marbles.Economy.Wallet
  alias Marbles.Racing
  alias Marbles.Racing.{Engine, Queue, Squads}
  alias Marbles.Schema.UserRaceStat
  alias Phoenix.PubSub

  @type dock_state :: :idle | :queued | :in_race

  @default_wage 50

  @impl true
  @spec mount(Phoenix.LiveView.unsigned_params(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(_params, session, socket) do
    user = MarblesWeb.Authz.fetch_current_user(session["user_id"])

    socket =
      socket
      |> assign(:current_user, user)
      |> assign_initial_state(user)

    if user && connected?(socket) do
      PubSub.subscribe(Marbles.PubSub, Queue.public_topic())
      PubSub.subscribe(Marbles.PubSub, Queue.user_topic(user.id))

      if socket.assigns.race do
        PubSub.subscribe(Marbles.PubSub, Engine.topic(socket.assigns.race.race_id))
      end
    end

    {:ok, socket, layout: false}
  end

  defp assign_initial_state(socket, nil) do
    socket
    |> assign(:authed, false)
    |> assign(:visible, false)
    |> assign(:state, :idle)
    |> assign(:stats, %{total: 0, brackets: %{}, bracket_step: 100})
    |> assign(:elo, nil)
    |> assign(:bracket, nil)
    |> assign(:wage, @default_wage)
    |> assign(:wallet_coins, 0)
    |> assign(:squads, [])
    |> assign(:selected_squad_id, nil)
    |> assign(:collapsed, false)
    |> assign(:queued_at, nil)
    |> assign(:race, nil)
  end

  defp assign_initial_state(socket, user) do
    squads = Squads.list_user_squads(user.id)
    elo = fetch_elo(user.id)
    stats = Racing.queue_stats()
    bracket = div(elo, max(stats.bracket_step, 1))
    wallet_coins = Wallet.balances(user.id).coins

    {state, queued_at, wage} =
      case Queue.user_status(user.id) do
        :idle -> {:idle, nil, @default_wage}
        %{wage: wage, joined_at: at} -> {:queued, at, wage}
      end

    race = build_initial_race(user.id)

    state =
      cond do
        race -> :in_race
        true -> state
      end

    socket
    |> assign(:authed, true)
    |> assign(:visible, true)
    |> assign(:state, state)
    |> assign(:stats, stats)
    |> assign(:elo, elo)
    |> assign(:bracket, bracket)
    |> assign(:wage, wage)
    |> assign(:wallet_coins, wallet_coins)
    |> assign(:squads, squads)
    |> assign(:selected_squad_id, default_squad_id(squads))
    |> assign(:collapsed, false)
    |> assign(:queued_at, queued_at)
    |> assign(:race, race)
  end

  defp refresh_wallet(%{assigns: %{current_user: nil}} = socket), do: socket

  defp refresh_wallet(socket) do
    coins = Wallet.balances(socket.assigns.current_user.id).coins
    assign(socket, :wallet_coins, coins)
  end

  defp build_initial_race(user_id) do
    case Racing.current_race_for(user_id) do
      nil ->
        nil

      race_id ->
        case Engine.pot_snapshot(race_id) do
          {:ok, %{pot_coins: pot}} ->
            %{race_id: race_id, pot: pot, leaderboard: [], finished?: false}

          _ ->
            %{race_id: race_id, pot: 0, leaderboard: [], finished?: false}
        end
    end
  end

  defp default_squad_id([]), do: nil
  defp default_squad_id([first | _]), do: first.id

  defp fetch_elo(user_id) do
    case Marbles.Repo.get_by(UserRaceStat, user_id: user_id) do
      %UserRaceStat{elo: elo} -> elo
      nil -> 1000
    end
  end

  # ----- handle_info --------------------------------------------------------

  @impl true
  def handle_info({:queue_stats, stats}, socket) do
    bracket = socket.assigns.elo && div(socket.assigns.elo, max(stats.bracket_step, 1))
    {:noreply, socket |> assign(:stats, stats) |> assign(:bracket, bracket)}
  end

  def handle_info({:queued, info}, socket) do
    {:noreply,
     socket
     |> assign(:state, :queued)
     |> assign(:queued_at, System.monotonic_time(:millisecond))
     |> assign(:bracket, info[:bracket] || socket.assigns.bracket)}
  end

  def handle_info({:left, :insufficient_funds}, socket) do
    {:noreply,
     socket
     |> assign(:state, :idle)
     |> assign(:queued_at, nil)
     |> put_flash(:error, "Dropped from queue: insufficient coins.")
     |> refresh_wallet()}
  end

  def handle_info({:left, _reason}, socket) do
    {:noreply, socket |> assign(:state, :idle) |> assign(:queued_at, nil)}
  end

  def handle_info({:matched, race_id}, socket) do
    PubSub.subscribe(Marbles.PubSub, Engine.topic(race_id))

    {:noreply,
     socket
     |> assign(:state, :in_race)
     |> assign(:queued_at, nil)
     |> assign(:race, %{race_id: race_id, pot: 0, leaderboard: [], finished?: false})
     |> refresh_wallet()}
  end

  def handle_info({:setup, setup}, socket) do
    case socket.assigns.race do
      nil ->
        {:noreply, socket}

      race ->
        {:noreply, assign(socket, :race, Map.put(race, :pot, setup[:pot_coins] || race.pot))}
    end
  end

  def handle_info({:frames, frames}, socket) do
    case socket.assigns.race do
      nil ->
        {:noreply, socket}

      race ->
        leaderboard = leaderboard_from_frames(frames)
        socket = push_event(socket, "race:frames", %{frames: frames})
        {:noreply, assign(socket, :race, Map.put(race, :leaderboard, leaderboard))}
    end
  end

  def handle_info({:pot_updated, %{pot_coins: pot}}, socket) do
    case socket.assigns.race do
      nil -> {:noreply, socket}
      race -> {:noreply, assign(socket, :race, Map.put(race, :pot, pot))}
    end
  end

  def handle_info({:finished, _summary}, socket) do
    case socket.assigns.race do
      nil -> {:noreply, socket}
      race -> {:noreply, assign(socket, :race, Map.put(race, :finished?, true))}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # ----- handle_event -------------------------------------------------------

  @impl true
  def handle_event("select_squad", %{"squad_id" => id}, socket) do
    {:noreply, assign(socket, :selected_squad_id, id)}
  end

  def handle_event("set_wage", %{"wage" => wage}, socket) do
    {:noreply, assign(socket, :wage, max(parse_int(wage), 1))}
  end

  def handle_event("join", _params, socket) do
    user = socket.assigns.current_user

    cond do
      user == nil ->
        {:noreply, socket}

      socket.assigns.selected_squad_id == nil ->
        {:noreply, put_flash(socket, :error, "Pick a squad first.")}

      socket.assigns.wallet_coins < socket.assigns.wage ->
        {:noreply, put_flash(socket, :error, "Not enough coins for this wage.")}

      true ->
        case Racing.enqueue_quick_race(user.id, socket.assigns.selected_squad_id,
               wage: socket.assigns.wage
             ) do
          :ok -> {:noreply, socket}
          {:error, reason} -> {:noreply, put_flash(socket, :error, queue_error(reason))}
        end
    end
  end

  def handle_event("leave", _params, socket) do
    if user = socket.assigns.current_user do
      Racing.leave_queue(user.id)
    end

    {:noreply, socket}
  end

  def handle_event("wage_more", %{"amount" => amount}, socket) do
    user = socket.assigns.current_user
    race = socket.assigns.race
    coins = parse_int(amount)

    cond do
      user == nil or race == nil ->
        {:noreply, socket}

      coins <= 0 ->
        {:noreply, put_flash(socket, :error, "Wage must be > 0.")}

      true ->
        with :ok <- Wallet.ensure_affordable(user.id, %{coins: coins}),
             :ok <- Wallet.debit(user.id, %{coins: coins}),
             :ok <- Engine.add_wage(race.race_id, user.id, coins) do
          {:noreply, refresh_wallet(socket)}
        else
          {:error, :insufficient_coins} ->
            {:noreply, put_flash(socket, :error, "Not enough coins.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not wage: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("toggle_collapse", _params, socket) do
    {:noreply, assign(socket, :collapsed, not socket.assigns.collapsed)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :visible, false)}
  end

  def handle_event("show", _params, socket) do
    socket =
      socket
      |> assign(:visible, true)
      |> assign(:collapsed, false)
      |> refresh_wallet()

    {:noreply, socket}
  end

  def handle_event("dismiss_race", _params, socket) do
    {:noreply, socket |> assign(:state, :idle) |> assign(:race, nil)}
  end

  # ----- helpers ------------------------------------------------------------

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(_), do: 0

  defp queue_error(:already_queued), do: "Already in queue."
  defp queue_error(:squad_not_owned), do: "That squad isn't yours."
  defp queue_error(:insufficient_funds), do: "Not enough coins."
  defp queue_error(other), do: "Could not join: #{inspect(other)}."

  defp leaderboard_from_frames([]), do: []

  defp leaderboard_from_frames(frames) do
    last = List.last(frames)

    last.marbles
    |> Enum.sort_by(& &1.rank)
    |> Enum.take(8)
    |> Enum.map(fn m -> %{id: m.id, rank: m.rank, progress: m.z, status: m.status} end)
  end

  # ----- render -------------------------------------------------------------

  @impl true
  def render(%{authed: false} = assigns), do: ~H""

  def render(assigns) do
    ~H"""
    <div
      id="race-dock-root"
      phx-hook="RaceDock"
      data-collapsed={if @collapsed, do: "true", else: "false"}
    >
      <%= if @visible do %>
        <div
          id="race-dock"
          class="fixed bottom-4 right-4 z-40 hidden w-[360px] max-w-[90vw] md:block"
        >
          <div class="flex flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100/95 shadow-2xl backdrop-blur">
            <header
              data-role="drag-handle"
              class="flex cursor-grab select-none items-center justify-between gap-2 border-b border-base-300 bg-base-200/60 px-3 py-2 active:cursor-grabbing"
            >
              <div class="flex items-center gap-2 min-w-0">
                <span class={[
                  "inline-block size-2 shrink-0 rounded-full",
                  @state == :idle && "bg-base-content/40",
                  @state == :queued && "bg-warning animate-pulse",
                  @state == :in_race && "bg-success animate-pulse"
                ]} />
                <span class="text-sm font-semibold tracking-wide">Race</span>
                <span :if={@state == :queued} class="truncate text-xs text-base-content/60">
                  Queued · bracket {@bracket}
                </span>
                <span :if={@state == :in_race} class="truncate text-xs text-base-content/60">
                  In race
                </span>
              </div>
              <div class="flex items-center gap-1">
                <button
                  type="button"
                  phx-click="toggle_collapse"
                  id="race-dock-collapse"
                  class="rounded p-1 hover:bg-base-300/60"
                  aria-label={if @collapsed, do: "Expand", else: "Collapse"}
                >
                  <.icon
                    name={if @collapsed, do: "hero-chevron-up", else: "hero-chevron-down"}
                    class="size-4"
                  />
                </button>
                <button
                  type="button"
                  phx-click="close"
                  id="race-dock-close"
                  class="rounded p-1 hover:bg-base-300/60"
                  aria-label="Close dock"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </header>

            <div :if={not @collapsed} class="overflow-auto p-3" data-role="dock-body">
              <%= case @state do %>
                <% :idle -> %>
                  {render_idle(assigns)}
                <% :queued -> %>
                  {render_queued(assigns)}
                <% :in_race -> %>
                  {render_race(assigns)}
              <% end %>
            </div>
          </div>
        </div>
      <% else %>
        <button
          type="button"
          id="race-dock-reopen"
          phx-click="show"
          class="fixed bottom-4 right-4 z-40 hidden md:flex items-center gap-2 rounded-full border border-base-300 bg-base-100/95 px-3 py-2 text-xs font-semibold shadow-lg backdrop-blur hover:bg-base-200"
        >
          <.icon name="hero-bolt" class="size-4 text-primary" /> Race
        </button>
      <% end %>
    </div>
    """
  end

  defp render_idle(assigns) do
    ~H"""
    <div class="space-y-3">
      {render_pyramid(assigns)}

      <%= if @squads == [] do %>
        <div class="rounded-xl border border-dashed border-base-300 p-3 text-center text-xs text-base-content/70">
          You don't have a squad. <.link navigate={~p"/roster"} class="link">Build one →</.link>
        </div>
      <% else %>
        <div class="space-y-2">
          <label class="text-xs uppercase tracking-wider text-base-content/60">Squad</label>
          <div class="flex flex-wrap gap-1">
            <button
              :for={squad <- @squads}
              type="button"
              phx-click="select_squad"
              phx-value-squad_id={squad.id}
              id={"dock-squad-#{squad.id}"}
              class={[
                "rounded-full border px-2 py-0.5 text-xs transition",
                @selected_squad_id == squad.id && "border-primary bg-primary/10",
                @selected_squad_id != squad.id && "border-base-300 hover:bg-base-200/40"
              ]}
            >
              {squad.name}
            </button>
          </div>
        </div>

        <form phx-change="set_wage" class="space-y-1">
          <div class="flex items-center justify-between">
            <label class="text-xs uppercase tracking-wider text-base-content/60">Wage (coins)</label>
            <span class="text-xs text-base-content/60">
              Balance: <span class="font-mono">{@wallet_coins}</span>
            </span>
          </div>
          <input
            type="number"
            name="wage"
            value={@wage}
            min="1"
            max={@wallet_coins}
            class="input input-sm input-bordered w-full"
          />
        </form>

        <% can_afford = @wallet_coins >= @wage and @wage > 0 %>
        <button
          type="button"
          phx-click="join"
          id="dock-join"
          disabled={not can_afford}
          class={[
            "btn btn-sm w-full rounded-full",
            can_afford && "btn-primary",
            not can_afford && "btn-disabled"
          ]}
        >
          <.icon name="hero-bolt" class="size-4" />
          <%= if can_afford do %>
            Find race
          <% else %>
            Not enough coins
          <% end %>
        </button>
      <% end %>
    </div>
    """
  end

  defp render_queued(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <span class="text-xs text-base-content/60">Searching for opponents…</span>
        <span class="loading loading-spinner loading-xs text-warning" />
      </div>

      {render_pyramid(assigns)}

      <div class="rounded-xl border border-base-300 p-3 text-center">
        <div class="text-3xl font-mono font-bold">{@stats.total}</div>
        <div class="text-xs text-base-content/60">in queue (you included)</div>
      </div>

      <div class="flex items-center justify-between text-xs">
        <span>Wage: <span class="font-mono">{@wage}</span></span>
        <span>Bracket {@bracket}</span>
      </div>

      <button
        type="button"
        phx-click="leave"
        id="dock-leave"
        class="btn btn-error btn-sm w-full rounded-full"
      >
        Leave queue
      </button>
    </div>
    """
  end

  defp render_race(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <div class="space-y-0.5">
          <p class="text-xs uppercase tracking-wider text-base-content/60">Live pot</p>
          <p class="font-mono text-2xl font-bold">{@race.pot}</p>
        </div>
        <.link navigate={~p"/race/#{@race.race_id}"} class="btn btn-ghost btn-xs">
          Open viewer <.icon name="hero-arrow-right" class="size-3" />
        </.link>
      </div>

      <canvas
        id="race-dock-canvas"
        data-role="mini-canvas"
        class="block w-full rounded-lg bg-black"
        style="aspect-ratio: 16 / 9;"
      />

      <div :if={@race.leaderboard != []} class="space-y-1 text-xs">
        <p class="uppercase tracking-wider text-base-content/60">Top racers</p>
        <ol class="space-y-1">
          <li
            :for={entry <- Enum.take(@race.leaderboard, 4)}
            class="flex items-center justify-between gap-2"
          >
            <span class="font-mono text-base-content/60">#{entry.rank}</span>
            <span class="flex-1 truncate">{String.slice(entry.id, 0, 8)}</span>
            <span class="text-base-content/60">{Float.round(entry.progress, 1)}m</span>
          </li>
        </ol>
      </div>

      <form phx-change="wage_more" class="flex items-center gap-2">
        <input
          type="number"
          name="amount"
          min="1"
          placeholder="+coins"
          class="input input-bordered input-xs w-20"
        />
        <button type="submit" id="dock-wage-more" class="btn btn-secondary btn-xs flex-1 rounded-full">
          Wage more
        </button>
      </form>

      <div :if={@race.finished?} class="flex items-center justify-between gap-2">
        <span class="text-xs text-base-content/70">Race finished.</span>
        <button
          type="button"
          phx-click="dismiss_race"
          id="dock-dismiss"
          class="btn btn-ghost btn-xs"
        >
          Dismiss
        </button>
      </div>
    </div>
    """
  end

  defp render_pyramid(assigns) do
    sorted = assigns.stats.brackets |> Enum.sort_by(&elem(&1, 0))
    max_count = sorted |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end)
    assigns = assigns |> assign(:rows, sorted) |> assign(:max_count, max(max_count, 1))

    ~H"""
    <div class="space-y-1">
      <p class="text-xs uppercase tracking-wider text-base-content/60">Live brackets</p>
      <div :if={@rows == []} class="text-xs text-base-content/60">No players queued yet.</div>
      <div :for={{bracket, count} <- @rows} class="flex items-center gap-2 text-xs">
        <span class="w-16 font-mono text-base-content/60">
          {bracket * @stats.bracket_step}+
        </span>
        <div class="flex-1 overflow-hidden rounded-full bg-base-300/40">
          <div
            class={[
              "h-2 rounded-full",
              @bracket == bracket && "bg-primary",
              @bracket != bracket && "bg-base-content/40"
            ]}
            style={"width: #{count / @max_count * 100}%; min-width: 6px;"}
          />
        </div>
        <span class={[
          "w-6 text-right font-mono",
          @bracket == bracket && "text-primary font-semibold"
        ]}>
          {count}
        </span>
      </div>
    </div>
    """
  end
end
