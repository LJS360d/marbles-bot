defmodule MarblesWeb.Admin.OwnerUsersLive do
  use MarblesWeb, :live_view
  alias Marbles.Accounts

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Users")
      |> assign(:current_scope, :owner_admin)
      |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Users", nil}])
      |> assign(:wide, true)
      |> assign(:page, 1)
      |> load_users()

    {:ok, socket}
  end

  defp load_users(socket) do
    page = socket.assigns.page
    {users, total} = Accounts.list_users(page: page, per_page: @per_page)
    total_pages = max(1, div(total + @per_page - 1, @per_page))

    socket
    |> assign(:users, users)
    |> assign(:total_users, total)
    |> assign(:total_pages, total_pages)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = String.to_integer(params["page"] || "1")

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_users()}
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
        <h1 class="text-2xl font-semibold">Users</h1>

        <div class="overflow-x-auto rounded-xl border border-base-300">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Display name</th>
                <th>Identities</th>
                <th>Role</th>
                <th>Currency</th>
                <th class="w-0">Collection</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={user <- @users}>
                <td>{Accounts.primary_display_name(user)}</td>
                <td>
                  {Enum.map(user.identities || [], fn i -> "#{i.platform}: #{i.username}" end)
                  |> Enum.join(", ")}
                </td>
                <td>{user.role}</td>
                <td>{user.currency}</td>
                <td>
                  <span class="flex gap-1">
                    <.link navigate={~p"/admin/owner/users/#{user.id}"} class="btn btn-ghost btn-xs">
                      View
                    </.link>
                    <.link
                      navigate={~p"/admin/owner/users/#{user.id}/edit"}
                      class="btn btn-ghost btn-xs"
                    >
                      Edit
                    </.link>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@total_pages > 1} class="flex justify-center gap-2">
          <.link
            :if={@page > 1}
            navigate={~p"/admin/owner/users?page=#{@page - 1}"}
            class="btn btn-sm"
          >
            Previous
          </.link>
          <span class="flex items-center px-2 text-sm">Page {@page} of {@total_pages}</span>
          <.link
            :if={@page < @total_pages}
            navigate={~p"/admin/owner/users?page=#{@page + 1}"}
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
