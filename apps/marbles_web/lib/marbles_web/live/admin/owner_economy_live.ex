defmodule MarblesWeb.Admin.OwnerEconomyLive do
  use MarblesWeb, :live_view
  alias Marbles.Economy.Admin
  alias Marbles.Leaderboards

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Economy")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Economy", nil}])
     |> assign(:page, 1)
     |> load_data()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 -> n
        _ -> 1
      end

    {:noreply, socket |> assign(:page, page) |> load_data()}
  end

  defp load_data(socket) do
    {cooldowns, total} = Admin.list_user_cooldowns(socket.assigns.page, @per_page)
    total_pages = max(1, div(total + @per_page - 1, @per_page))

    socket
    |> assign(:cooldowns, cooldowns)
    |> assign(:cooldowns_total, total)
    |> assign(:cooldowns_total_pages, total_pages)
    |> assign(:top_coins, Leaderboards.top_coins(5))
    |> assign(:top_collection, Leaderboards.top_collection_count(5))
    |> assign(:top_strongest, Leaderboards.top_strongest_marble(5))
  end

  defp fmt_eta(0), do: "ready"

  defp fmt_eta(sec) when sec < 3600 do
    "#{div(sec, 60)}m"
  end

  defp fmt_eta(sec) when sec < 86_400 do
    "#{div(sec, 3600)}h"
  end

  defp fmt_eta(sec) do
    "#{div(sec, 86_400)}d"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      wide={true}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h1 class="text-2xl font-semibold">Economy control panel</h1>
          <.link navigate={~p"/admin/owner/shop-items"} class="btn btn-primary btn-sm">
            Manage shop items
          </.link>
        </div>

        <section class="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <article class="rounded-xl border border-base-300 bg-base-200 p-4">
            <h2 class="text-sm font-semibold text-base-content/70">Top coins</h2>
            <ul class="mt-2 space-y-1 text-sm">
              <li :for={row <- @top_coins}>{row.rank}. {row.label} — {row.score}</li>
            </ul>
          </article>
          <article class="rounded-xl border border-base-300 bg-base-200 p-4">
            <h2 class="text-sm font-semibold text-base-content/70">Top collection</h2>
            <ul class="mt-2 space-y-1 text-sm">
              <li :for={row <- @top_collection}>{row.rank}. {row.label} — {row.score}</li>
            </ul>
          </article>
          <article class="rounded-xl border border-base-300 bg-base-200 p-4">
            <h2 class="text-sm font-semibold text-base-content/70">Top strongest</h2>
            <ul class="mt-2 space-y-1 text-sm">
              <li :for={row <- @top_strongest}>{row.rank}. {row.label} — {row.score}</li>
            </ul>
          </article>
        </section>

        <section class="rounded-xl border border-base-300 bg-base-200 p-4">
          <h2 class="text-lg font-semibold">User cooldowns and wallets</h2>
          <p class="text-sm text-base-content/70">
            Tracks `/daily` availability, current streak, and wallet balances.
          </p>

          <div class="mt-4 overflow-x-auto rounded-xl border border-base-300">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Daily cooldown</th>
                  <th>Streak</th>
                  <th>Coins</th>
                  <th>Dust</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @cooldowns}>
                  <td>{row.username || "User"}</td>
                  <td>{fmt_eta(row.seconds_until_daily)}</td>
                  <td>{row.streak || 0}</td>
                  <td>{row.currency}</td>
                  <td>{row.dust}</td>
                  <td>
                    <.link navigate={~p"/admin/owner/users/#{row.id}"} class="btn btn-ghost btn-xs">
                      Manage user
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@cooldowns == []} class="mt-3 text-sm text-base-content/60">No users yet.</p>

          <div :if={@cooldowns_total_pages > 1} class="mt-3 flex items-center justify-between">
            <span class="text-xs text-base-content/60">
              Page {@page} of {@cooldowns_total_pages} · {@cooldowns_total} users
            </span>
            <div class="flex gap-2">
              <.link
                :if={@page > 1}
                patch={~p"/admin/owner/economy?page=#{@page - 1}"}
                class="btn btn-sm"
              >
                Previous
              </.link>
              <.link
                :if={@page < @cooldowns_total_pages}
                patch={~p"/admin/owner/economy?page=#{@page + 1}"}
                class="btn btn-sm"
              >
                Next
              </.link>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
