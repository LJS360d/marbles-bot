defmodule MarblesWeb.MiningLive do
  @moduledoc "Public mining page — roster slots, current yield, claim."

  use MarblesWeb, :live_view

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
        |> assign(:roster, [])
        |> assign(:yield, nil)

      user ->
        {:ok, roster} = MineRoster.view(user.id)

        accrual = Mining.accrual_seconds(nil, DateTime.utc_now(), user.id)
        yield = Mining.compute_coins(user.id, accrual)

        socket
        |> assign(:roster, roster)
        |> assign(:yield, yield)
    end
  end

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
        <h1 class="text-3xl font-bold">Mines</h1>

        <div
          :if={!@current_user}
          class="rounded-2xl border border-base-300 bg-base-200/30 p-6 text-center text-sm text-base-content/60"
        >
          Log in to view your mine roster.
        </div>

        <div
          :if={@current_user && @yield}
          class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-5 space-y-3"
        >
          <h2 class="text-lg font-semibold">Current yield</h2>
          <div class="grid gap-3 grid-cols-2 sm:grid-cols-3">
            <div>
              <p class="text-xs text-base-content/60">Coins</p>
              <p class="text-2xl font-semibold">{@yield.coins}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/60">Slots filled</p>
              <p class="text-2xl font-semibold">{length(@roster)}</p>
            </div>
          </div>
          <p class="text-xs text-base-content/50">
            Claim via Discord <code>/mine claim</code> for now — web claim landing soon.
          </p>
        </div>

        <div
          :if={@current_user}
          class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-5 space-y-3"
        >
          <h2 class="text-lg font-semibold">Roster</h2>
          <ul :if={@roster != []} class="grid gap-2 grid-cols-2 sm:grid-cols-3 md:grid-cols-4">
            <li
              :for={entry <- @roster}
              class="rounded-xl border border-base-300 bg-base-200/50 p-2"
            >
              <p class="font-medium text-sm truncate">{entry[:name] || "—"}</p>
              <p class="text-[10px] text-base-content/60">Slot {entry[:slot]}</p>
            </li>
          </ul>
          <p :if={@roster == []} class="text-sm text-base-content/60">
            No marbles assigned. Use <code>/mine add &lt;marble&gt;</code> on Discord.
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
