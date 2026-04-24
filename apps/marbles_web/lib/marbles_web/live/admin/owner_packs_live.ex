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
      |> assign(:sort, "name")
      |> assign(:order, "asc")
      |> assign(:q, "")
      |> assign(:packs_base, ~p"/admin/owner/packs")
      |> assign(:per_page, @per_page)
      |> load_packs()

    {:ok, socket}
  end

  defp load_packs(socket) do
    page = socket.assigns[:page] || 1
    sort = socket.assigns.sort
    order = socket.assigns.order
    q = socket.assigns.q

    {packs, total} =
      Packs.list_packs(
        page: page,
        per_page: @per_page,
        sort: sort,
        order: order,
        q: q
      )

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
    |> assign(:search_form, to_form(%{"q" => q}))
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = parse_page(params["page"], 1)
    sort = params["sort"] || "name"
    order = parse_order(params["order"], "asc")
    q = params["q"] |> to_string() |> String.trim()

    socket =
      socket
      |> assign(:page, page)
      |> assign(:sort, sort)
      |> assign(:order, order)
      |> assign(:q, q)
      |> load_packs()

    max_p = socket.assigns.total_pages

    if page > max_p and max_p >= 1 do
      {:noreply,
       push_patch(socket,
         to:
           query_path(socket.assigns.packs_base, %{
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
         query_path(socket.assigns.packs_base, %{
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

  defp parse_order("desc", _), do: "desc"
  defp parse_order(_, default), do: default

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.header current_user={@current_user} />
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h1 class="text-2xl font-semibold">Packs</h1>
          <.link navigate={~p"/admin/owner/packs/new"} class="btn btn-primary btn-sm">
            New pack
          </.link>
        </div>

        <div class="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end sm:justify-between">
          <.form
            for={@search_form}
            id="admin-packs-search"
            phx-submit="search"
            class="flex flex-wrap items-end gap-2"
          >
            <.input field={@search_form[:q]} type="search" label="Search" placeholder="Pack name" />
            <button type="submit" class="btn btn-primary btn-sm">Search</button>
          </.form>
          <.link
            :if={@q != ""}
            patch={query_path(@packs_base, %{page: 1, sort: @sort, order: @order})}
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
                  base_path={@packs_base}
                  column="name"
                  label="Name"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
                <th>Banner</th>
                <.admin_sort_th
                  base_path={@packs_base}
                  column="cost"
                  label="Cost"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
                <th>Status</th>
                <.admin_sort_th
                  base_path={@packs_base}
                  column="marble_count"
                  label="Marbles"
                  sort={@sort}
                  order={@order}
                  q={@q}
                />
                <th class="w-0">Edit</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={pack <- @packs}>
                <td>{pack.name}</td>
                <td>
                  <%= if banner_url = @pack_banner_urls[pack.id] do %>
                    <a
                      href={banner_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-block"
                    >
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

        <.admin_paginator
          base_path={@packs_base}
          page={@page}
          total_pages={@total_pages}
          total_count={@total_packs}
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
