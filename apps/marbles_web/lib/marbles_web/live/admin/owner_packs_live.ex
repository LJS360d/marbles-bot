defmodule MarblesWeb.Admin.OwnerPacksLive do
  use MarblesWeb, :live_view
  alias Marbles.Packs
  alias Marbles.Assets

  @per_page 25

  defp pack_status(pack) do
    today = Date.utc_today()

    cond do
      pack.end_date && Date.compare(pack.end_date, today) == :lt -> "Ended"
      pack.start_date && Date.compare(pack.start_date, today) == :gt -> "Scheduled"
      true -> "Active"
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Packs")
      |> assign(:current_scope, :owner_admin)
      |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Packs", nil}])
      |> assign(:page, 1)
      |> load_packs()

    {:ok, socket}
  end

  defp load_packs(socket) do
    page = socket.assigns[:page] || 1
    {packs, total} = Packs.list_packs(page: page, per_page: @per_page)
    total_pages = max(1, div(total + @per_page - 1, @per_page))

    banner_urls =
      Map.new(packs, fn p ->
        {p.id, Assets.url_for_path(p.banner_path)}
      end)

    socket
    |> assign(:packs, packs)
    |> assign(:pack_banner_urls, banner_urls)
    |> assign(:total_packs, total)
    |> assign(:total_pages, total_pages)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = String.to_integer(params["page"] || "1")

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_packs()}
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
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h1 class="text-2xl font-semibold">Packs</h1>
          <.link navigate={~p"/admin/owner/packs/new"} class="btn btn-primary btn-sm">
            New pack
          </.link>
        </div>

        <div class="overflow-x-auto rounded-xl border border-base-300">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Name</th>
                <th>Banner</th>
                <th>Cost</th>
                <th>Status</th>
                <th>Marbles</th>
                <th class="w-0">Edit</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={pack <- @packs}>
                <td>{pack.name}</td>
                <td>
                  <%= if banner_url = @pack_banner_urls[pack.id] do %>
                    <a href={banner_url} target="_blank" rel="noopener noreferrer" class="inline-block">
                      <img
                        src={banner_url}
                        alt={pack.name}
                        class="max-h-16 max-w-16 h-16 w-16 object-cover rounded"
                      />
                    </a>
                  <% else %>
                    <span>—</span>
                  <% end %>
                </td>
                <td>{pack.cost}</td>
                <td>{pack_status(pack)}</td>
                <td>{length(pack.marbles || [])}</td>
                <td>
                  <.link
                    navigate={~p"/admin/owner/packs/#{pack.id}/edit"}
                    class="btn btn-ghost btn-xs"
                  >
                    Edit
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@total_packs == 0} class="text-sm text-base-content/60">
          No packs. Create one from the Owner admin or New pack.
        </p>

        <div :if={@total_pages > 1} class="flex justify-center gap-2">
          <.link
            :if={@page > 1}
            navigate={~p"/admin/owner/packs?page=#{@page - 1}"}
            class="btn btn-sm"
          >
            Previous
          </.link>
          <span class="flex items-center px-2 text-sm">Page {@page} of {@total_pages}</span>
          <.link
            :if={@page < @total_pages}
            navigate={~p"/admin/owner/packs?page=#{@page + 1}"}
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
