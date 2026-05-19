defmodule MarblesWeb.Admin.OwnerReplaysLive do
  @moduledoc "Owner-only paginated list of race replays."

  use MarblesWeb, :live_view

  alias Marbles.Audit
  alias Marbles.Racing.Replay

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Replays")
     |> assign(:current_scope, :owner_replays)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Replays", nil}])
     |> assign(:page, 1)
     |> assign(:detail, nil)
     |> load_replays()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 -> n
        _ -> 1
      end

    {:noreply, socket |> assign(:page, page) |> load_replays()}
  end

  defp load_replays(socket) do
    offset = (socket.assigns.page - 1) * @per_page
    {entries, total} = Replay.list_recent(@per_page, offset)

    socket
    |> assign(:entries, entries)
    |> assign(:total, total)
    |> assign(:per_page, @per_page)
  end

  @impl true
  def handle_event("show_detail", %{"id" => race_id}, socket) do
    case Replay.load(race_id) do
      {:ok, payload} -> {:noreply, assign(socket, :detail, %{race_id: race_id, payload: payload})}
      _ -> {:noreply, put_flash(socket, :error, "Replay could not be loaded.")}
    end
  end

  def handle_event("close_detail", _params, socket), do: {:noreply, assign(socket, :detail, nil)}

  def handle_event("delete", %{"id" => race_id}, socket) do
    {count, _} = Replay.delete_by_race(race_id)

    if count > 0 do
      Audit.log("replay.delete",
        actor_id: socket.assigns.current_user.id,
        target_type: "race_replay",
        target_id: race_id
      )
    end

    {:noreply,
     socket
     |> put_flash(:info, "Replay deleted.")
     |> load_replays()}
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
          <h1 class="text-2xl font-bold">Replays</h1>
          <span class="text-sm text-base-content/60">{@total} stored</span>
        </header>

        <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Race id</th>
                <th>Stored at</th>
                <th>Version</th>
                <th>Size</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @entries} id={"replay-row-#{r.id}"}>
                <td class="font-mono text-xs">
                  <.link href={~p"/race/#{r.race_id}"} class="hover:underline">{r.race_id}</.link>
                </td>
                <td class="font-mono text-xs">
                  {Calendar.strftime(r.inserted_at, "%Y-%m-%d %H:%M:%S")}
                </td>
                <td>{r.version}</td>
                <td class="text-xs">{byte_size(r.payload || "") |> format_bytes()}</td>
                <td class="text-right space-x-2">
                  <button
                    type="button"
                    phx-click="show_detail"
                    phx-value-id={r.race_id}
                    class="btn btn-ghost btn-xs"
                  >
                    View
                  </button>
                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={r.race_id}
                    data-confirm="Delete this replay?"
                    id={"delete-#{r.id}"}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </td>
              </tr>
              <tr :if={@entries == []}>
                <td colspan="5" class="text-center text-base-content/60 py-6">No replays yet.</td>
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
              patch={~p"/admin/owner/replays?page=#{@page - 1}"}
              class="btn btn-ghost btn-sm"
            >
              Previous
            </.link>
            <.link
              :if={@page < ceil(@total / @per_page)}
              patch={~p"/admin/owner/replays?page=#{@page + 1}"}
              class="btn btn-ghost btn-sm"
            >
              Next
            </.link>
          </div>
        </div>
      </section>

      <div :if={@detail} class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
        <div class="w-full max-w-3xl rounded-2xl bg-base-100 p-5 shadow-xl space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold font-mono text-sm">Replay {@detail.race_id}</h2>
            <button phx-click="close_detail" class="btn btn-ghost btn-sm">
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <pre
            class="rounded bg-base-200 p-2 text-[10px] overflow-auto max-h-[60vh]"
            phx-no-curly-interpolation
          ><code><%= Jason.encode!(@detail.payload, pretty: true) %></code></pre>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_bytes(b) when b < 1024, do: "#{b}B"
  defp format_bytes(b) when b < 1024 * 1024, do: "#{div(b, 1024)}KB"
  defp format_bytes(b), do: "#{Float.round(b / 1_048_576, 1)}MB"
end
