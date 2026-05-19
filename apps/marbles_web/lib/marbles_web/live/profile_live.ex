defmodule MarblesWeb.ProfileLive do
  @moduledoc "Public profile page — identity, wallets, race stats, collection, upgrades, settings."

  use MarblesWeb, :live_view

  alias Marbles.Accounts
  alias Marbles.Economy.Wallet
  alias Marbles.Repo
  alias Marbles.Schema.{UserMarble, UserRaceStat}

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Profile")
     |> assign(:current_scope, :profile)
     |> assign(:show_login_modal, false)
     |> load_state()}
  end

  defp load_state(socket) do
    case socket.assigns[:current_user] do
      nil ->
        socket

      user ->
        wallet = Wallet.balances(user.id)
        race_stat = Repo.get_by(UserRaceStat, user_id: user.id)

        marble_count =
          Repo.aggregate(from(m in UserMarble, where: m.user_id == ^user.id), :count, :id)

        socket
        |> assign(:wallet, wallet)
        |> assign(:race_stat, race_stat)
        |> assign(:marble_count, marble_count)
        |> assign(:display_name, Accounts.primary_display_name(user))
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
        <div
          :if={!@current_user}
          class="rounded-2xl border border-base-300 bg-base-200/30 p-6 text-center text-sm text-base-content/60"
        >
          Log in to view your profile.
        </div>

        <div :if={@current_user} class="space-y-6">
          <%!-- Identity card --%>
          <div class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-5 flex items-center gap-4">
            <div class="size-16 rounded-full bg-base-300 flex items-center justify-center text-2xl font-bold">
              {String.first(@display_name || "?")}
            </div>
            <div class="min-w-0 flex-1">
              <h1 class="text-2xl font-bold truncate">{@display_name}</h1>
              <p class="text-xs text-base-content/60 font-mono">{@current_user.id}</p>
            </div>
          </div>

          <%!-- Stats grid --%>
          <div class="grid gap-3 grid-cols-2 md:grid-cols-4">
            <div class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4">
              <p class="text-xs text-base-content/60">Coins</p>
              <p class="text-xl font-semibold">{@wallet[:coins] || 0}</p>
            </div>
            <div class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4">
              <p class="text-xs text-base-content/60">Dust</p>
              <p class="text-xl font-semibold">{@wallet[:dust] || 0}</p>
            </div>
            <div class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4">
              <p class="text-xs text-base-content/60">Marbles</p>
              <p class="text-xl font-semibold">{@marble_count}</p>
            </div>
            <div class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4">
              <p class="text-xs text-base-content/60">ELO</p>
              <p class="text-xl font-semibold">{(@race_stat && @race_stat.elo) || 1000}</p>
            </div>
          </div>

          <%!-- Race stats card --%>
          <div
            :if={@race_stat}
            class="rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur p-5 space-y-2"
          >
            <h2 class="text-lg font-semibold">Race record</h2>
            <div class="grid gap-3 grid-cols-3 text-sm">
              <div>
                <p class="text-xs text-base-content/60">Races</p>
                <p class="font-semibold">{@race_stat.races_entered}</p>
              </div>
              <div>
                <p class="text-xs text-base-content/60">Wins</p>
                <p class="font-semibold">{@race_stat.race_wins}</p>
              </div>
              <div>
                <p class="text-xs text-base-content/60">Best streak</p>
                <p class="font-semibold">{@race_stat.best_streak}</p>
              </div>
            </div>
          </div>

          <%!-- Tiles --%>
          <div class="grid gap-3 sm:grid-cols-2">
            <.link
              navigate={~p"/profile/upgrade"}
              class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 hover:bg-base-200 transition-colors"
            >
              <p class="font-semibold">Upgrade marble</p>
              <p class="text-xs text-base-content/60">Spend dust to power up a marble</p>
            </.link>
            <form action={~p"/logout"} method="post">
              <%!-- <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              --%>
              <input type="hidden" name="_method" value="delete" />
              <button
                type="submit"
                class="w-full rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 text-left hover:bg-error/10 transition-colors"
              >
                <p class="font-semibold text-error">Log out</p>
                <p class="text-xs text-base-content/60">End your session</p>
              </button>
            </form>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
