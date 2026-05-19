defmodule MarblesWeb.Admin.OwnerAdminLive do
  use MarblesWeb, :live_view
  alias Marbles.Analytics
  alias Marbles.Analytics.AdminDashboard
  alias Marbles.Guilds

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    Phoenix.PubSub.subscribe(Marbles.PubSub, "admin_dashboard")

    socket =
      socket
      |> assign(:page_title, "Owner admin")
      |> assign(:current_scope, :owner_admin)
      |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}])
      |> assign(:guilds_insights_sort, params["guilds_sort"] || "channels_desc")
      |> assign(:guilds_insights_page, parse_page(params["guilds_page"]))
      |> load_dashboard()

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    sort = params["guilds_sort"] || socket.assigns[:guilds_insights_sort] || "channels_desc"

    page =
      if params["guilds_page"] do
        parse_page(params["guilds_page"])
      else
        socket.assigns[:guilds_insights_page] || 1
      end

    {:noreply,
     socket
     |> assign(:guilds_insights_sort, sort)
     |> assign(:guilds_insights_page, page)
     |> load_dashboard()}
  end

  @spec parse_page(String.t() | nil) :: pos_integer() | nil

  defp parse_page(nil), do: nil

  defp parse_page(param) do
    case Integer.parse(param) do
      {page, ""} when page > 0 -> page
      _ -> nil
    end
  end

  @impl true
  @spec handle_info({:admin_dashboard, :stats_updated}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:admin_dashboard, :stats_updated}, socket) do
    pulls_today = Analytics.pulls_today()
    spawns_today = Analytics.spawns_today()
    max_events = max(pulls_today + spawns_today, 1)

    {:noreply,
     socket
     |> assign(:pulls_today, pulls_today)
     |> assign(:spawns_today, spawns_today)
     |> assign(:max_events, max_events)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("guilds_insights_sort", %{"sort" => sort}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/owner?guilds_sort=#{sort}&guilds_page=1")}
  end

  @spec load_dashboard(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_dashboard(socket) do
    snapshot = AdminDashboard.snapshot()

    {guilds_insights, guilds_insights_total} =
      Guilds.list_guilds_insights(
        socket.assigns[:guilds_insights_sort] || "channels_desc",
        socket.assigns[:guilds_insights_page] || 1,
        8
      )

    socket
    |> assign(:guilds_count, snapshot.guilds_count)
    |> assign(:users_count, snapshot.users_count)
    |> assign(:pulls_today, snapshot.pulls_today)
    |> assign(:spawns_today, snapshot.spawns_today)
    |> assign(:marbles_count, snapshot.marbles_count)
    |> assign(:packs_count, snapshot.packs_count)
    |> assign(:teams_count, snapshot.teams_count)
    |> assign(:max_events, snapshot.max_events)
    |> assign(:guilds_insights, guilds_insights)
    |> assign(:guilds_insights_total, guilds_insights_total)
    |> assign(:guilds_insights_sort, socket.assigns[:guilds_insights_sort] || "channels_desc")
    |> assign(:guilds_insights_page, socket.assigns[:guilds_insights_page] || 1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6 sm:space-y-8" id="owner-admin-root">
        <h1 class="text-2xl font-semibold text-base-content">Owner admin</h1>

        <section class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          <.link
            navigate={~p"/admin/owner/users"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Users</p>
            <p class="mt-1 text-2xl font-semibold">{@users_count}</p>
          </.link>
          <.link
            navigate={~p"/admin/owner/guilds"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Guilds</p>
            <p class="mt-1 text-2xl font-semibold">{@guilds_count}</p>
          </.link>
          <.link
            navigate={~p"/admin/owner/economy"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Economy</p>
            <p class="mt-1 text-base font-semibold">Cooldowns · Shop · Wallets</p>
          </.link>
          <.link
            navigate={~p"/admin/owner/packs"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <div class="flex items-start justify-between gap-2">
              <div>
                <p class="text-sm font-medium text-base-content/70">Packs</p>
                <p class="mt-1 text-2xl font-semibold">{@packs_count}</p>
              </div>
            </div>
          </.link>
          <.link
            navigate={~p"/admin/owner/marbles"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Marbles</p>
            <p class="mt-1 text-2xl font-semibold">{@marbles_count}</p>
          </.link>
          <.link
            navigate={~p"/admin/owner/teams"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Teams</p>
            <p class="mt-1 text-2xl font-semibold">{@teams_count}</p>
          </.link>
          <.link
            navigate={~p"/admin/owner/system"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">System</p>
            <p class="mt-1 text-base font-semibold">Phoenix LiveDashboard →</p>
          </.link>
        </section>

        <section class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm sm:p-6">
          <div class="flex items-center gap-2">
            <h2 class="text-lg font-semibold text-base-content">Today&apos;s activity</h2>
            <span class="rounded-full bg-success/20 px-2 py-0.5 text-xs font-medium text-success">
              Live
            </span>
          </div>
          <div class="mt-3 flex gap-6 text-sm">
            <div>
              <span class="text-base-content/70">Pulls</span>
              <span class="font-semibold">{@pulls_today}</span>
            </div>
            <div>
              <span class="text-base-content/70">Spawns</span>
              <span class="font-semibold">{@spawns_today}</span>
            </div>
          </div>
        </section>

        <section class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm sm:p-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-lg font-semibold text-base-content">Guilds Insights</h2>
            <.link navigate={~p"/admin/owner/guilds"} class="text-sm text-primary hover:underline">
              View all
            </.link>
          </div>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <span class="text-sm text-base-content/70">Sort:</span>
            <.form for={%{}} phx-change="guilds_insights_sort" id="guilds-insights-sort-form">
              <select name="sort" class="select select-bordered select-sm max-w-xs">
                <option value="channels_desc" selected={@guilds_insights_sort == "channels_desc"}>
                  Channels (most first)
                </option>
                <option value="channels" selected={@guilds_insights_sort == "channels"}>
                  Channels (least first)
                </option>
                <option value="name" selected={@guilds_insights_sort == "name"}>Name A–Z</option>
                <option value="name_desc" selected={@guilds_insights_sort == "name_desc"}>
                  Name Z–A
                </option>
              </select>
            </.form>
          </div>
          <ul class="mt-3 space-y-2">
            <li
              :for={{guild, ch_count} <- @guilds_insights}
              class="flex items-center gap-3 rounded-lg border border-base-300 bg-base-100 px-3 py-2"
            >
              <.guild_avatar guild={guild} class="h-8 w-8 shrink-0 rounded-full" />
              <span class="min-w-0 flex-1 truncate font-medium">{guild.name}</span>
              <span class="shrink-0 text-sm text-base-content/70">{ch_count} channels</span>
            </li>
          </ul>
          <p :if={@guilds_insights == []} class="py-4 text-sm text-base-content/60">No guilds yet.</p>
          <div
            :if={@guilds_insights_total > 8}
            class="mt-3 flex items-center justify-between border-t border-base-300 pt-3"
          >
            <span class="text-xs text-base-content/60">
              Page {@guilds_insights_page} of {max(1, ceil(@guilds_insights_total / 8))}
            </span>
            <div class="flex gap-1">
              <.link
                :if={@guilds_insights_page > 1}
                patch={
                  ~p"/admin/owner?guilds_sort=#{@guilds_insights_sort}&guilds_page=#{@guilds_insights_page - 1}"
                }
                class="btn btn-ghost btn-sm"
              >
                Previous
              </.link>
              <.link
                :if={@guilds_insights_page < max(1, ceil(@guilds_insights_total / 8))}
                patch={
                  ~p"/admin/owner?guilds_sort=#{@guilds_insights_sort}&guilds_page=#{@guilds_insights_page + 1}"
                }
                class="btn btn-ghost btn-sm"
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
