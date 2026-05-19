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
      |> assign(:sort, "inserted_at")
      |> assign(:order, "desc")
      |> assign(:q, "")
      |> assign(:users_base, ~p"/admin/owner/users")
      |> assign(:per_page, @per_page)
      |> load_users()

    {:ok, socket}
  end

  defp load_users(socket) do
    page = socket.assigns.page
    sort = socket.assigns.sort
    order = socket.assigns.order
    q = socket.assigns.q

    {users, total} =
      Accounts.list_users(
        page: page,
        per_page: @per_page,
        sort: sort,
        order: order,
        q: q
      )

    total_pages = max(1, div(total + @per_page - 1, @per_page))

    socket
    |> assign(:users, users)
    |> assign(:total_users, total)
    |> assign(:total_pages, total_pages)
    |> assign(:search_form, to_form(%{"q" => q}))
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = parse_page(params["page"], 1)
    sort = params["sort"] || "inserted_at"
    order = parse_order(params["order"], "desc")
    q = params["q"] |> to_string() |> String.trim()

    socket =
      socket
      |> assign(:page, page)
      |> assign(:sort, sort)
      |> assign(:order, order)
      |> assign(:q, q)
      |> load_users()

    max_p = socket.assigns.total_pages

    if page > max_p and max_p >= 1 do
      {:noreply,
       push_patch(socket,
         to:
           query_path(socket.assigns.users_base, %{
             page: max_p,
             sort: sort,
             order: order,
             q: q
           })
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    q = q |> to_string() |> String.trim()

    {:noreply,
     push_patch(socket,
       to:
         query_path(socket.assigns.users_base, %{
           page: 1,
           sort: socket.assigns.sort,
           order: socket.assigns.order,
           q: q
         })
     )}
  end

  defp parse_page(nil, default), do: default

  defp parse_page(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp parse_order("asc", _), do: "asc"
  defp parse_order(_, default), do: default

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6">
        <h1 class="text-2xl font-semibold">Users</h1>

        <div class="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end sm:justify-between">
          <.form
            for={@search_form}
            id="admin-users-search"
            phx-submit="search"
            class="flex flex-wrap items-end gap-2"
          >
            <.input
              field={@search_form[:q]}
              type="search"
              label="Search"
              placeholder="Name or username"
            />
            <button type="submit" class="btn btn-primary btn-sm">Search</button>
          </.form>
          <.link
            :if={@q != ""}
            patch={query_path(@users_base, %{page: 1, sort: @sort, order: @order})}
            class="btn btn-ghost btn-sm"
          >
            Clear search
          </.link>
        </div>

        <div class="overflow-x-auto rounded-xl border border-base-300">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <.admin_sort_th
                  base_path={@users_base}
                  column="display_name"
                  label="Display name"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
                <th>Identities</th>
                <.admin_sort_th
                  base_path={@users_base}
                  column="role"
                  label="Role"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
                <.admin_sort_th
                  base_path={@users_base}
                  column="currency"
                  label="Currency"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
                <.admin_sort_th
                  base_path={@users_base}
                  column="dust"
                  label="Dust"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
                <.admin_sort_th
                  base_path={@users_base}
                  column="inserted_at"
                  label="Joined"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
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
                <td>{user.dust || 0}</td>
                <td class="whitespace-nowrap text-sm text-base-content/70">
                  {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
                </td>
                <td>
                  <span class="flex gap-1">
                    <.link
                      navigate={~p"/admin/owner/users/#{user.id}"}
                      class="btn btn-outline btn-xs"
                    >
                      View
                    </.link>
                    <.link
                      navigate={~p"/admin/owner/users/#{user.id}/edit"}
                      class="btn btn-outline btn-xs"
                    >
                      Edit
                    </.link>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.admin_paginator
          base_path={@users_base}
          page={@page}
          total_pages={@total_pages}
          total_count={@total_users}
          per_page={@per_page}
          sort={@sort}
          order={@order}
          q={@q}
        />
      </div>
    </Layouts.app>
    """
  end
end
