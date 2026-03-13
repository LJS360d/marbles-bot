defmodule MarblesWeb.Admin.OwnerPacksLive do
  use MarblesWeb, :live_view
  alias Marbles.Packs

  @impl true
  def mount(_params, _session, socket) do
    packs = Packs.list_all_packs()

    {:ok,
     socket
     |> assign(:page_title, "Packs")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Packs", nil}])
     |> assign(:packs, packs)}
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
                <th>Cost</th>
                <th>Active</th>
                <th>Marbles</th>
                <th class="w-0">Edit</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={pack <- @packs}>
                <td>{pack.name}</td>
                <td>{pack.cost}</td>
                <td>{pack.active}</td>
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
        <p :if={@packs == []} class="text-sm text-base-content/60">
          No packs. Create one from the Owner admin or New pack.
        </p>
      </div>
    </Layouts.app>
    """
  end
end
