defmodule MarblesWeb.Admin.OwnerAnalyticsLive do
  @moduledoc "Owner-only historical analytics drill-down."

  use MarblesWeb, :live_view

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Schema.AnalyticsEvent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Analytics")
     |> assign(:current_scope, :owner_analytics)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Analytics", nil}])
     |> assign(:range, "7d")
     |> load_series()}
  end

  defp load_series(socket) do
    {bucket_count, bucket_seconds, granularity_label} =
      case socket.assigns.range do
        "24h" -> {24, 3600, "hour"}
        "7d" -> {7, 86_400, "day"}
        "30d" -> {30, 86_400, "day"}
        _ -> {7, 86_400, "day"}
      end

    now = DateTime.utc_now()
    from_dt = DateTime.add(now, -bucket_count * bucket_seconds, :second)

    rows =
      from(a in AnalyticsEvent,
        where: a.inserted_at >= ^from_dt,
        select: {a.event_type, a.inserted_at}
      )
      |> Repo.all()

    series =
      Enum.reduce(rows, %{}, fn {type, ts}, acc ->
        bucket = bucket_for(ts, from_dt, bucket_seconds)
        Map.update(acc, type, %{bucket => 1}, &Map.update(&1, bucket, 1, fn n -> n + 1 end))
      end)

    socket
    |> assign(:series, series)
    |> assign(:bucket_count, bucket_count)
    |> assign(:granularity_label, granularity_label)
    |> assign(:from_dt, from_dt)
    |> assign(:bucket_seconds, bucket_seconds)
  end

  defp bucket_for(ts, from_dt, bucket_seconds) do
    diff = DateTime.diff(ts, from_dt, :second)
    div(diff, bucket_seconds)
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, socket |> assign(:range, range) |> load_series()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-5">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Analytics</h1>
          <div class="tabs tabs-boxed">
            <button
              :for={r <- ["24h", "7d", "30d"]}
              phx-click="set_range"
              phx-value-range={r}
              class={["tab tab-sm", @range == r && "tab-active"]}
            >
              {r}
            </button>
          </div>
        </header>

        <p class="text-xs text-base-content/60">
          Showing {@bucket_count} {@granularity_label}s ending now.
        </p>

        <div class="space-y-4">
          <div
            :for={{type, buckets} <- Enum.sort_by(@series, fn {t, _} -> t end)}
            id={"chart-#{type}"}
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4"
          >
            <div class="flex items-center justify-between mb-2">
              <h2 class="font-semibold font-mono text-sm">{type}</h2>
              <span class="text-xs text-base-content/60">
                total {Enum.sum(Map.values(buckets))}
              </span>
            </div>
            <.bar_chart buckets={buckets} count={@bucket_count} />
          </div>
          <div
            :if={@series == %{}}
            class="rounded-2xl border border-base-300 bg-base-200/30 p-6 text-center text-sm text-base-content/60"
          >
            No analytics events in this range.
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :buckets, :map, required: true
  attr :count, :integer, required: true

  defp bar_chart(assigns) do
    max_val = max(1, Map.values(assigns.buckets) |> Enum.max(fn -> 0 end))
    assigns = assign(assigns, :max_val, max_val)

    ~H"""
    <div class="flex items-end gap-0.5 h-24">
      <%= for i <- 0..(@count - 1) do %>
        <% v = Map.get(@buckets, i, 0) %>
        <% pct = max(2, min(100, div(v * 100, @max_val))) %>
        <div
          class="flex-1 bg-primary/70 rounded-t hover:bg-primary transition-colors"
          style={"height: #{pct}%"}
          title={"bucket #{i}: #{v}"}
        />
      <% end %>
    </div>
    """
  end
end
