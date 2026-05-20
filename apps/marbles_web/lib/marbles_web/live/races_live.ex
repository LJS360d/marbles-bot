defmodule MarblesWeb.RacesLive do
  @moduledoc "Public race hub: embedded queue join/wager, live bracket display, race link."

  use MarblesWeb, :live_view

  alias Marbles.Economy.Wallet
  alias Marbles.Racing
  alias Marbles.Racing.{Events, Queue, Squads}
  alias Marbles.Schema.UserRaceStat

  @default_wage 50
  @min_wage 1
  @max_wage 100_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Marbles.PubSub, Queue.public_topic())
    end

    user = socket.assigns[:current_user]

    {:ok,
     socket
     |> assign(:page_title, "Races")
     |> assign(:current_scope, :race)
     |> assign(:show_login_modal, false)
     |> assign(:user_elo, fetch_user_elo(user))
     |> assign(:wage_input, Integer.to_string(@default_wage))
     |> load_user_state(user)
     |> load_state()}
  end

  defp load_state(socket) do
    socket
    |> assign(:queue_stats, Racing.queue_stats())
    |> assign(:upcoming, Events.list_upcoming(5))
  end

  defp load_user_state(socket, nil) do
    socket
    |> assign(:squads, [])
    |> assign(:selected_squad_id, nil)
    |> assign(:wallet, nil)
    |> assign(:queue_entry, :idle)
  end

  defp load_user_state(socket, user) do
    squads = Squads.list_user_squads(user.id)
    wallet = Wallet.balances(user.id)
    entry = Queue.user_status(user.id)

    selected =
      socket.assigns[:selected_squad_id] ||
        case squads do
          [first | _] -> first.id
          _ -> nil
        end

    socket
    |> assign(:squads, squads)
    |> assign(:selected_squad_id, selected)
    |> assign(:wallet, wallet)
    |> assign(:queue_entry, entry)
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

  defp pot_estimate(stats, my_wage) do
    avg =
      if stats.total > 0 do
        # Rough estimate: assume average wage tracks user's wage. Could be smarter.
        my_wage
      else
        my_wage
      end

    party = max(stats.min_party, min(stats.max_party, stats.total + 1))
    avg * party
  end

  @impl true
  def handle_info({:queue_stats, stats}, socket),
    do: {:noreply, assign(socket, :queue_stats, stats)}

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_squad", %{"squad_id" => id}, socket) do
    {:noreply, assign(socket, :selected_squad_id, id)}
  end

  def handle_event("wage_change", %{"wage" => raw}, socket) do
    {:noreply, assign(socket, :wage_input, raw)}
  end

  def handle_event("join", _params, socket) do
    user = socket.assigns[:current_user]
    squad_id = socket.assigns.selected_squad_id

    cond do
      user == nil ->
        {:noreply, redirect(socket, to: ~p"/login")}

      squad_id == nil ->
        {:noreply, put_flash(socket, :error, "Build a squad first.")}

      true ->
        case parse_wage(socket.assigns.wage_input) do
          {:ok, wage} ->
            case Racing.enqueue_quick_race(user.id, squad_id, wage: wage) do
              :ok ->
                {:noreply, load_user_state(socket, user)}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, join_error(reason))}
            end

          :error ->
            {:noreply, put_flash(socket, :error, "Wager must be a positive number.")}
        end
    end
  end

  def handle_event("leave", _params, socket) do
    user = socket.assigns[:current_user]

    if user do
      Queue.leave(user.id)
      {:noreply, load_user_state(socket, user) |> put_flash(:info, "Left the queue.")}
    else
      {:noreply, socket}
    end
  end

  defp parse_wage(raw) when is_binary(raw) do
    case Integer.parse(String.trim(raw)) do
      {n, ""} when n >= @min_wage and n <= @max_wage -> {:ok, n}
      _ -> :error
    end
  end

  defp join_error(:already_queued), do: "You're already in the queue."
  defp join_error(:in_race), do: "You're already in a race."
  defp join_error(:invalid_squad), do: "That squad is invalid."
  defp join_error(:insufficient_funds), do: "Not enough coins for that wager."
  defp join_error(:no_squads), do: "Build a squad first."
  defp join_error(other), do: "Could not join: #{inspect(other)}."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      race_state={@race_state}
      current_race_id={@current_race_id}
      current_user={@current_user}
      current_scope={@current_scope}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-4 py-4">
        <header class="flex flex-wrap items-end justify-between gap-3">
          <h1 class="text-2xl font-bold">Races</h1>
          <span :if={@wallet} class="text-xs text-base-content/60 font-mono">
            Wallet: {@wallet.coins} coins
          </span>
        </header>

        <.queue_panel
          race_state={@race_state}
          current_race_id={@current_race_id}
          current_user={@current_user}
          squads={@squads}
          selected_squad_id={@selected_squad_id}
          wage_input={@wage_input}
          queue_entry={@queue_entry}
          queue_stats={@queue_stats}
          user_bracket={user_bracket(@user_elo, @queue_stats.bracket_step)}
        />

        <div class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-2">
          <h2 class="text-base font-semibold">Upcoming events</h2>
          <ul :if={@upcoming != []} class="divide-y divide-base-300">
            <li :for={ev <- @upcoming} class="py-2 flex items-center justify-between">
              <div>
                <p class="font-medium">{ev.name}</p>
                <p class="text-xs text-base-content/60">
                  {Calendar.strftime(ev.start_time, "%b %d %H:%M UTC")}
                </p>
              </div>
              <.link navigate={~p"/events/#{ev.id}"} class="btn btn-ghost btn-sm">Open</.link>
            </li>
          </ul>
          <p :if={@upcoming == []} class="text-sm text-base-content/60">
            No upcoming events.
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :race_state, :atom, required: true
  attr :current_race_id, :any, default: nil
  attr :current_user, :any, default: nil
  attr :squads, :list, required: true
  attr :selected_squad_id, :any, default: nil
  attr :wage_input, :string, required: true
  attr :queue_entry, :any, required: true
  attr :queue_stats, :map, required: true
  attr :user_bracket, :any, default: nil

  defp queue_panel(%{current_user: nil} = assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-3">
      <h2 class="text-base font-semibold">Quick race</h2>
      <p class="text-sm text-base-content/70">Sign in to join the queue.</p>
      <.link href={~p"/login"} class="btn btn-primary btn-sm rounded-full">Log in</.link>
      <.bracket_chips stats={@queue_stats} user_bracket={@user_bracket} />
    </section>
    """
  end

  defp queue_panel(%{race_state: :in_race} = assigns) do
    ~H"""
    <section class="rounded-3xl border border-orange-500/40 bg-orange-500/10 backdrop-blur p-4 space-y-3">
      <div class="flex items-center gap-3">
        <span class="size-3 rounded-full bg-orange-500 animate-pulse" />
        <h2 class="text-base font-semibold text-orange-400">Your race is running</h2>
      </div>
      <p class="text-sm text-base-content/70">Watch your squad live.</p>
      <.link
        :if={@current_race_id}
        navigate={~p"/race/#{@current_race_id}"}
        class="btn btn-warning btn-sm rounded-full"
      >
        Watch race <.icon name="hero-arrow-right" class="size-4" />
      </.link>
      <p :if={!@current_race_id} class="text-xs text-base-content/60">
        Race link will appear here once the engine starts.
      </p>
    </section>
    """
  end

  defp queue_panel(%{race_state: :queued, queue_entry: %{} = entry} = assigns) do
    assigns = assign(assigns, :entry, entry)

    ~H"""
    <section class="rounded-3xl border border-success/40 bg-success/10 backdrop-blur p-4 space-y-3">
      <div class="flex items-center gap-3">
        <span class="size-3 rounded-full bg-success animate-pulse" />
        <h2 class="text-base font-semibold text-success">In queue</h2>
      </div>
      <dl class="grid grid-cols-3 gap-2 text-sm">
        <div>
          <dt class="text-xs text-base-content/60 uppercase tracking-wider">Wager</dt>
          <dd class="font-mono font-semibold">{@entry.wage} coins</dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60 uppercase tracking-wider">Bracket</dt>
          <dd class="font-mono font-semibold">
            ELO {@entry.bracket * @queue_stats.bracket_step}–{(@entry.bracket + 1) *
              @queue_stats.bracket_step - 1}
          </dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60 uppercase tracking-wider">Est. pot</dt>
          <dd class="font-mono font-semibold">{pot_estimate(@queue_stats, @entry.wage)}</dd>
        </div>
      </dl>
      <.bracket_chips stats={@queue_stats} user_bracket={@entry.bracket} />
      <button
        type="button"
        phx-click="leave"
        class="btn btn-ghost btn-sm rounded-full text-error"
      >
        Leave queue
      </button>
    </section>
    """
  end

  defp queue_panel(%{squads: []} = assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-3">
      <h2 class="text-base font-semibold">Quick race</h2>
      <p class="text-sm text-base-content/70">You need a squad first.</p>
      <.link navigate={~p"/squads"} class="btn btn-primary btn-sm rounded-full">
        Build a squad
      </.link>
      <.bracket_chips stats={@queue_stats} user_bracket={@user_bracket} />
    </section>
    """
  end

  defp queue_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-3">
      <div class="flex items-center justify-between gap-2">
        <h2 class="text-base font-semibold">Quick race</h2>
        <p class="text-xs text-base-content/60 font-mono">
          {@queue_stats.total} queued
        </p>
      </div>

      <form phx-change="select_squad" id="races-squad-form" class="space-y-1">
        <label class="text-xs uppercase tracking-wider text-base-content/60">Squad</label>
        <select name="squad_id" class="select select-bordered select-sm w-full">
          <option :for={s <- @squads} value={s.id} selected={s.id == @selected_squad_id}>
            {s.name} (slot {s.slot_index + 1})
          </option>
        </select>
      </form>

      <form phx-change="wage_change" phx-submit="join" id="races-wage-form" class="space-y-1">
        <label class="text-xs uppercase tracking-wider text-base-content/60">Wager (coins)</label>
        <div class="flex gap-2">
          <input
            type="number"
            name="wage"
            value={@wage_input}
            min="1"
            max="100000"
            class="input input-bordered input-sm w-32"
          />
          <button type="submit" class="btn btn-primary btn-sm rounded-full grow">
            <.icon name="hero-bolt" class="size-4" /> Join queue
          </button>
        </div>
      </form>

      <.bracket_chips stats={@queue_stats} user_bracket={@user_bracket} />
    </section>
    """
  end

  attr :stats, :map, required: true
  attr :user_bracket, :any, default: nil

  defp bracket_chips(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2 pt-1 border-t border-base-300/50">
      <span class="text-xs uppercase tracking-wider text-base-content/60 self-center">
        Live queue
      </span>
      <%= if map_size(@stats.brackets) == 0 do %>
        <span class="text-xs text-base-content/60">empty</span>
      <% else %>
        <%= for {bracket, count} <- Enum.sort_by(@stats.brackets, &elem(&1, 0)) do %>
          <div class={[
            "rounded-full border px-2 py-0.5 text-xs",
            @user_bracket == bracket && "border-primary bg-primary/20 text-primary",
            @user_bracket != bracket && "border-base-300"
          ]}>
            <span class="font-mono">
              {bracket * @stats.bracket_step}–{(bracket + 1) * @stats.bracket_step - 1}
            </span>
            <span class="ml-1 font-semibold">{count}</span>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
