defmodule MarblesWeb.Admin.OwnerAdminLive do
  use MarblesWeb, :live_view
  alias Marbles.Analytics
  alias Marbles.Guilds
  alias Marbles.Accounts
  alias Marbles.Catalog
  alias Marbles.Repo
  alias Marbles.Schema.Marble

  @impl true
  def mount(params, _session, socket) do
    Phoenix.PubSub.subscribe(Marbles.PubSub, "admin_dashboard")

    socket =
      socket
      |> assign(:page_title, "Owner admin")
      |> assign(:current_scope, :owner_admin)
      |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}])
      |> assign(:memory_insights_enabled, true)
      |> assign(:guilds_insights_sort, params["guilds_sort"] || "channels_desc")
      |> assign(:guilds_insights_page, parse_page(params["guilds_page"]))
      |> load_dashboard()

    {:ok, socket}
  end

  @impl true
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
  def handle_info(:tick_memory, socket) do
    if socket.assigns[:memory_insights_enabled] do
      Process.send_after(self(), :tick_memory, 5_000)
    end

    memory = :erlang.memory()
    total_mem = memory[:total] || 0
    beam_total_mb = div(total_mem, 1024 * 1024)

    memory_breakdown = %{
      beam_total_mb: beam_total_mb,
      process_mb: div(memory[:processes] || 0, 1024 * 1024),
      atom_mb: div(memory[:atom] || 0, 1024 * 1024),
      binary_mb: div(memory[:binary] || 0, 1024 * 1024),
      code_mb: div(memory[:code] || 0, 1024 * 1024),
      ets_mb: div(memory[:ets] || 0, 1024 * 1024),
      system_mb: div(memory[:system] || 0, 1024 * 1024)
    }

    {:noreply, assign(socket, :memory_breakdown, memory_breakdown)}
  end

  @impl true
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
  def handle_event("toggle_memory_insights", _params, socket) do
    enabled = !socket.assigns[:memory_insights_enabled]

    socket =
      socket
      |> assign(:memory_insights_enabled, enabled)
      |> then(fn s ->
        if enabled,
          do: push_event(s, "persist_memory_insights", %{enabled: true}),
          else: push_event(s, "persist_memory_insights", %{enabled: false})
      end)

    if enabled, do: send(self(), :tick_memory)
    {:noreply, socket}
  end

  @impl true
  def handle_event("memory_insights_init", %{"enabled" => enabled}, socket) do
    socket = assign(socket, :memory_insights_enabled, enabled)

    socket =
      if enabled,
        do: push_event(socket, "persist_memory_insights", %{enabled: true}),
        else: push_event(socket, "persist_memory_insights", %{enabled: false})

    if enabled, do: send(self(), :tick_memory)
    {:noreply, socket}
  end

  @impl true
  def handle_event("guilds_insights_sort", %{"sort" => sort}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/owner?guilds_sort=#{sort}&guilds_page=1")}
  end

  defp load_dashboard(socket) do
    memory = :erlang.memory()
    total_mem = memory[:total] || 0
    guilds_count = Analytics.guilds_count()
    {_users, users_total} = Accounts.list_users(per_page: 1)
    pulls_today = Analytics.pulls_today()
    spawns_today = Analytics.spawns_today()
    marbles_count = Repo.aggregate(Marble, :count, :id)
    packs_count = Catalog.list_all_packs() |> length()
    teams_count = Catalog.list_teams() |> length()
    max_events = max(pulls_today + spawns_today, 1)

    memory_breakdown = %{
      beam_total_mb: div(total_mem, 1024 * 1024),
      process_mb: div(memory[:processes] || 0, 1024 * 1024),
      atom_mb: div(memory[:atom] || 0, 1024 * 1024),
      binary_mb: div(memory[:binary] || 0, 1024 * 1024),
      code_mb: div(memory[:code] || 0, 1024 * 1024),
      ets_mb: div(memory[:ets] || 0, 1024 * 1024),
      system_mb: div(memory[:system] || 0, 1024 * 1024)
    }

    {guilds_insights, guilds_insights_total} =
      Guilds.list_guilds_insights(
        socket.assigns[:guilds_insights_sort] || "channels_desc",
        socket.assigns[:guilds_insights_page] || 1,
        8
      )

    socket
    |> assign(:memory_breakdown, memory_breakdown)
    |> assign(:guilds_count, guilds_count)
    |> assign(:users_count, users_total)
    |> assign(:pulls_today, pulls_today)
    |> assign(:spawns_today, spawns_today)
    |> assign(:marbles_count, marbles_count)
    |> assign(:packs_count, packs_count)
    |> assign(:teams_count, teams_count)
    |> assign(:max_events, max_events)
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
      wide={true}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6 sm:space-y-8" id="owner-admin-root" phx-hook="OwnerAdminMemoryInsights">
        <h1 class="text-2xl font-semibold text-base-content">Owner admin</h1>

        <section class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <.link
            navigate={~p"/admin/owner/guilds"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Guilds</p>
            <p class="mt-1 text-2xl font-semibold">{@guilds_count}</p>
          </.link>
          <.link
            navigate={~p"/admin/owner/users"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Users</p>
            <p class="mt-1 text-2xl font-semibold">{@users_count}</p>
          </.link>
          <.link
            navigate={~p"/admin/owner/marbles"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Marbles</p>
            <p class="mt-1 text-2xl font-semibold">{@marbles_count}</p>
          </.link>
          <div class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm">
            <div class="flex items-start justify-between gap-2">
              <div>
                <p class="text-sm font-medium text-base-content/70">Packs</p>
                <p class="mt-1 text-2xl font-semibold">{@packs_count}</p>
              </div>
              <.link navigate={~p"/admin/owner/packs/new"} class="btn btn-primary btn-sm shrink-0">
                New pack
              </.link>
            </div>
            <.link
              navigate={~p"/admin/owner/packs"}
              class="mt-2 block text-sm text-primary hover:underline"
            >
              View packs
            </.link>
          </div>
          <.link
            navigate={~p"/admin/owner/teams"}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm transition-colors hover:bg-base-300"
          >
            <p class="text-sm font-medium text-base-content/70">Teams</p>
            <p class="mt-1 text-2xl font-semibold">{@teams_count}</p>
          </.link>
        </section>

        <section
          :if={@memory_insights_enabled}
          class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm sm:p-6"
        >
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-lg font-semibold text-base-content">Memory</h2>
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked
                phx-click="toggle_memory_insights"
                class="toggle toggle-sm"
              />
              <span>Gathering</span>
            </label>
          </div>
          <div class="mt-4">
            <.memory_stacked_bar breakdown={@memory_breakdown} />
          </div>
          <p class="mt-2 text-xs text-base-content/60">
            BEAM total {@memory_breakdown.beam_total_mb} MB · Processes {@memory_breakdown.process_mb} · Atom {@memory_breakdown.atom_mb} · Binary {@memory_breakdown.binary_mb} · Code {@memory_breakdown.code_mb} · ETS {@memory_breakdown.ets_mb} · System {@memory_breakdown.system_mb} MB
          </p>
        </section>

        <section
          :if={!@memory_insights_enabled}
          class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm sm:p-6"
        >
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-lg font-semibold text-base-content">Memory</h2>
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input type="checkbox" phx-click="toggle_memory_insights" class="toggle toggle-sm" />
              <span>Gathering</span>
            </label>
          </div>
          <p class="mt-2 text-sm text-base-content/60">
            Memory insights are paused. Enable to resume.
          </p>
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

  attr :breakdown, :map, required: true

  def memory_stacked_bar(assigns) do
    b = assigns.breakdown
    beam_mb = max(b.beam_total_mb, 1)

    segments = [
      {"Processes", b.process_mb, "bg-primary"},
      {"Atom", b.atom_mb, "bg-secondary"},
      {"Binary", b.binary_mb, "bg-accent"},
      {"Code", b.code_mb, "bg-info"},
      {"ETS", b.ets_mb, "bg-warning"},
      {"System", b.system_mb, "bg-base-content/30"}
    ]

    assigns = assign(assigns, :segments, segments)
    assigns = assign(assigns, :beam_mb, beam_mb)

    ~H"""
    <div class="flex items-center gap-3">
      <div class="h-6 min-w-0 flex-1 overflow-hidden rounded bg-base-300 flex">
        <%= for {label, mb, color} <- @segments do %>
          <% pct = if @beam_mb > 0, do: min(100, div(mb * 100, @beam_mb)), else: 0 %>
          <div
            :if={pct > 0}
            class={["h-full min-w-[2px] transition-all", color]}
            style={"width: #{max(pct, 0.5)}%"}
            title={"#{label} #{mb} MB"}
          />
        <% end %>
      </div>
      <span class="w-14 shrink-0 text-right text-sm font-medium">{@beam_mb} MB</span>
    </div>
    """
  end
end
