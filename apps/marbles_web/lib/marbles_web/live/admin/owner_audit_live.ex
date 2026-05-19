defmodule MarblesWeb.Admin.OwnerAuditLive do
  @moduledoc "Owner-only paginated, filterable audit log."

  use MarblesWeb, :live_view

  alias Marbles.Audit

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log")
     |> assign(:current_scope, :owner_audit)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Audit log", nil}])
     |> assign(:filters, %{})
     |> assign(:page, 1)
     |> assign(:detail, nil)
     |> load_entries()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      actor_id: blank_to_nil(params["actor_id"]),
      target_type: blank_to_nil(params["target_type"]),
      target_id: blank_to_nil(params["target_id"]),
      action: blank_to_nil(params["action"])
    }

    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 -> n
        _ -> 1
      end

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, page)
     |> load_entries()}
  end

  defp load_entries(socket) do
    filters = socket.assigns.filters
    page = socket.assigns.page
    offset = (page - 1) * @per_page

    {entries, total} =
      filters
      |> Map.put(:limit, @per_page)
      |> Map.put(:offset, offset)
      |> Audit.list()

    socket
    |> assign(:entries, entries)
    |> assign(:total, total)
    |> assign(:per_page, @per_page)
  end

  @impl true
  def handle_event("filter", params, socket) do
    qs =
      %{
        actor_id: params["actor_id"],
        target_type: params["target_type"],
        target_id: params["target_id"],
        action: params["action"],
        page: 1
      }
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> URI.encode_query()

    {:noreply, push_patch(socket, to: ~p"/admin/owner/audit-log?#{qs}")}
  end

  def handle_event("show_detail", %{"id" => id}, socket) do
    detail = Enum.find(socket.assigns.entries, &(&1.id == id))
    {:noreply, assign(socket, :detail, detail)}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :detail, nil)}
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
          <h1 class="text-2xl font-bold">Audit log</h1>
          <span class="text-sm text-base-content/60">{@total} entries</span>
        </header>

        <.form
          for={%{}}
          id="audit-filter-form"
          phx-submit="filter"
          class="grid gap-2 grid-cols-1 md:grid-cols-5 rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-3"
        >
          <input
            type="text"
            name="action"
            value={@filters[:action] || ""}
            placeholder="action"
            class="input input-bordered input-sm"
          />
          <input
            type="text"
            name="actor_id"
            value={@filters[:actor_id] || ""}
            placeholder="actor_id"
            class="input input-bordered input-sm"
          />
          <input
            type="text"
            name="target_type"
            value={@filters[:target_type] || ""}
            placeholder="target_type"
            class="input input-bordered input-sm"
          />
          <input
            type="text"
            name="target_id"
            value={@filters[:target_id] || ""}
            placeholder="target_id"
            class="input input-bordered input-sm"
          />
          <button type="submit" class="btn btn-primary btn-sm">Filter</button>
        </.form>

        <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>Time</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Target</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={e <- @entries} id={"audit-row-#{e.id}"}>
                <td class="font-mono text-xs whitespace-nowrap">
                  {Calendar.strftime(e.inserted_at, "%Y-%m-%d %H:%M:%S")}
                </td>
                <td class="font-mono text-xs">{short_id(e.actor_id)}</td>
                <td class="font-medium text-xs">{e.action}</td>
                <td class="text-xs">
                  <span :if={e.target_type}>{e.target_type}/{short_id(e.target_id)}</span>
                </td>
                <td class="text-right">
                  <button
                    type="button"
                    phx-click="show_detail"
                    phx-value-id={e.id}
                    class="btn btn-ghost btn-xs"
                  >
                    View
                  </button>
                </td>
              </tr>
              <tr :if={@entries == []}>
                <td colspan="5" class="text-center text-base-content/60 py-6">No entries.</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex items-center justify-between">
          <span class="text-xs text-base-content/60">
            Page {@page} of {max(1, ceil(@total / @per_page))}
          </span>
          <div class="flex gap-1">
            <.link
              :if={@page > 1}
              patch={page_url(@filters, @page - 1)}
              class="btn btn-ghost btn-sm"
            >
              Previous
            </.link>
            <.link
              :if={@page < ceil(@total / @per_page)}
              patch={page_url(@filters, @page + 1)}
              class="btn btn-ghost btn-sm"
            >
              Next
            </.link>
          </div>
        </div>
      </section>

      <div :if={@detail} class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
        <div class="w-full max-w-2xl rounded-2xl bg-base-100 p-5 shadow-xl space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold">Audit entry</h2>
            <button phx-click="close_detail" class="btn btn-ghost btn-sm">
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <dl class="grid grid-cols-3 gap-x-3 gap-y-1.5 text-xs">
            <dt class="text-base-content/60">Time</dt>
            <dd class="col-span-2 font-mono">
              {Calendar.strftime(@detail.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </dd>
            <dt class="text-base-content/60">Action</dt>
            <dd class="col-span-2 font-medium">{@detail.action}</dd>
            <dt class="text-base-content/60">Actor</dt>
            <dd class="col-span-2 font-mono">{@detail.actor_id || "—"}</dd>
            <dt class="text-base-content/60">Target</dt>
            <dd class="col-span-2 font-mono">
              {@detail.target_type || "—"} / {@detail.target_id || "—"}
            </dd>
          </dl>
          <div class="grid gap-3 md:grid-cols-2">
            <div>
              <p class="text-xs font-medium mb-1">Before</p>
              <pre
                class="rounded bg-base-200 p-2 text-[10px] overflow-auto max-h-48"
                phx-no-curly-interpolation
              ><code><%= json_pretty(@detail.before) %></code></pre>
            </div>
            <div>
              <p class="text-xs font-medium mb-1">After</p>
              <pre
                class="rounded bg-base-200 p-2 text-[10px] overflow-auto max-h-48"
                phx-no-curly-interpolation
              ><code><%= json_pretty(@detail.after) %></code></pre>
            </div>
          </div>
          <div :if={@detail.metadata not in [nil, %{}]}>
            <p class="text-xs font-medium mb-1">Metadata</p>
            <pre
              class="rounded bg-base-200 p-2 text-[10px] overflow-auto max-h-32"
              phx-no-curly-interpolation
            ><code><%= json_pretty(@detail.metadata) %></code></pre>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp short_id(nil), do: "—"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0..7)
  defp short_id(id), do: inspect(id)

  defp page_url(filters, page) do
    qs =
      filters
      |> Enum.into(%{page: page})
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> URI.encode_query()

    "/admin/owner/audit-log?#{qs}"
  end

  defp json_pretty(nil), do: "—"
  defp json_pretty(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp json_pretty(other), do: inspect(other)
end
