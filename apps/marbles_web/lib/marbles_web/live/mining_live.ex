defmodule MarblesWeb.MiningLive do
  @moduledoc "Public mining page — interactive roster slot editor, current yield, claim."

  use MarblesWeb, :live_view

  alias Marbles.Collection
  alias Marbles.Economy.{Mining, MineRoster}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Mines")
     |> assign(:current_scope, :mine)
     |> assign(:show_login_modal, false)
     |> load_state()}
  end

  defp load_state(socket) do
    case socket.assigns[:current_user] do
      nil ->
        socket
        |> assign(:mine_marbles, [])
        |> assign(:mine_add_options, [])
        |> assign(:yield, nil)

      user ->
        mine_marbles = MineRoster.list_assigned_user_marbles(user.id)
        accrual = Mining.accrual_seconds(nil, DateTime.utc_now(), user.id)
        yield = Mining.compute_coins(user.id, accrual)

        socket
        |> assign(:mine_marbles, mine_marbles)
        |> assign(:mine_add_options, mine_add_candidates(user.id, mine_marbles))
        |> assign(:yield, yield)
    end
  end

  defp mine_add_candidates(user_id, mine_marbles) do
    {collection, _total} = Collection.list_user_inventory(user_id, page: 1, per_page: 200)
    in_mine = mine_marbles |> Enum.map(& &1.id) |> MapSet.new()
    Enum.filter(collection, fn um -> not MapSet.member?(in_mine, um.id) end)
  end

  @impl true
  def handle_event("add_mine_slot", %{"user_marble_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_mine_slot", %{"user_marble_id" => id}, socket) do
    user = socket.assigns.current_user

    case MineRoster.add_user_marble(user.id, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marble added to mining roster.")
         |> load_state()}

      {:error, :roster_full} ->
        {:noreply, put_flash(socket, :error, "Mining roster is full (max 5).")}

      {:error, :already_in_roster} ->
        {:noreply, put_flash(socket, :error, "Already mining that marble.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Marble not found.")}
    end
  end

  def handle_event("remove_mine", %{"user_marble_id" => id}, socket) do
    user = socket.assigns.current_user

    case MineRoster.remove_user_marble(user.id, id) do
      {:ok, _} ->
        {:noreply, load_state(socket)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Not in mining roster.")}
    end
  end

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
        <h1 class="text-2xl font-bold">Mines</h1>

        <div
          :if={!@current_user}
          class="rounded-2xl border border-base-300 bg-base-200/30 p-4 text-center text-sm text-base-content/60"
        >
          Log in to view your mine roster.
        </div>

        <div
          :if={@current_user && @yield}
          class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-2"
        >
          <h2 class="text-base font-semibold">Current yield</h2>
          <div class="grid gap-3 grid-cols-2 sm:grid-cols-3">
            <div>
              <p class="text-xs text-base-content/60">Coins</p>
              <p class="text-xl font-semibold">{@yield.coins}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/60">Slots filled</p>
              <p class="text-xl font-semibold">{length(@mine_marbles)}</p>
            </div>
          </div>
        </div>

        <section
          :if={@current_user}
          class="rounded-3xl border border-base-300 bg-base-100/60 p-4 backdrop-blur space-y-3"
        >
          <div class="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 class="text-base font-bold">Mining roster</h2>
              <p class="text-xs text-base-content/60">
                Up to 5 marbles earn passive coins toward your daily claim.
              </p>
            </div>
            <form :if={@mine_add_options != []} phx-change="add_mine_slot" id="mine-add-form">
              <label class="text-xs uppercase tracking-wider text-base-content/60">Add marble</label>
              <select
                name="user_marble_id"
                class="select select-bordered select-sm w-full max-w-xs mt-1"
              >
                <option value="">Choose…</option>
                <option :for={um <- @mine_add_options} value={um.id}>
                  {um.marble.name} · Lv.{um.level}
                </option>
              </select>
            </form>
          </div>

          <%= if @mine_marbles == [] do %>
            <p class="text-sm text-base-content/60">No marbles mining yet.</p>
          <% else %>
            <ul class="grid gap-2 sm:grid-cols-2">
              <li
                :for={um <- @mine_marbles}
                class="flex items-center justify-between gap-2 rounded-2xl border border-base-300 bg-base-200/20 px-3 py-2 text-sm"
              >
                <div class="min-w-0">
                  <p class="font-medium truncate">{um.marble.name}</p>
                  <p class="text-xs text-base-content/60">
                    Lv.{um.level} · {rarity_stars(um.marble.rarity)}
                  </p>
                </div>
                <div class="flex shrink-0 gap-1">
                  <button
                    type="button"
                    phx-click="remove_mine"
                    phx-value-user_marble_id={um.id}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Remove
                  </button>
                </div>
              </li>
            </ul>
          <% end %>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
