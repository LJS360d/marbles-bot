defmodule MarblesWeb.Admin.OwnerMarblesLive do
  use MarblesWeb, :live_view
  alias Marbles.Catalog

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Marbles")
      |> assign(:current_scope, :owner_admin)
      |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Marbles", nil}])
      |> assign(:page, 1)
      |> load_marbles()

    {:ok, socket}
  end

  defp load_marbles(socket) do
    page = socket.assigns[:page] || 1
    {marbles, total} = Catalog.list_marbles(page: page, per_page: @per_page)
    total_pages = max(1, div(total + @per_page - 1, @per_page))

    socket
    |> assign(:marbles, marbles)
    |> assign(:total_marbles, total)
    |> assign(:total_pages, total_pages)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = String.to_integer(params["page"] || "1")

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_marbles()}
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
        <h1 class="text-2xl font-semibold">Marbles</h1>

        <div class="overflow-x-auto rounded-xl border border-base-300">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Name</th>
                <th>Edition</th>
                <th>Role</th>
                <th>Rarity</th>
                <th>Team</th>
                <th class="w-0">Edit</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={m <- @marbles}>
                <td>{m.name}</td>
                <td>{m.edition}</td>
                <td>{m.role}</td>
                <td>{m.rarity}</td>
                <td>{if m.team, do: m.team.name, else: "—"}</td>
                <td>
                  <.link navigate={~p"/admin/owner/marbles/#{m.id}/edit"} class="btn btn-ghost btn-xs">
                    Edit
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@total_pages > 1} class="flex justify-center gap-2">
          <.link
            :if={@page > 1}
            navigate={~p"/admin/owner/marbles?page=#{@page - 1}"}
            class="btn btn-sm"
          >
            Previous
          </.link>
          <span class="flex items-center px-2 text-sm">Page {@page} of {@total_pages}</span>
          <.link
            :if={@page < @total_pages}
            navigate={~p"/admin/owner/marbles?page=#{@page + 1}"}
            class="btn btn-sm"
          >
            Next
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
