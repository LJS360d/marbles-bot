defmodule MarblesWeb.AdminTable do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: MarblesWeb.Endpoint,
    router: MarblesWeb.Router,
    statics: MarblesWeb.static_paths()

  @spec query_path(String.t(), map()) :: String.t()
  def query_path(base_path, params) when is_binary(base_path) and is_map(params) do
    q =
      params
      |> Enum.flat_map(fn
        {k, v} when is_atom(k) -> [{Atom.to_string(k), v}]
        {k, v} when is_binary(k) -> [{k, v}]
      end)
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> Map.new(fn {k, v} -> {k, param_to_string(v)} end)
      |> URI.encode_query()

    if q == "", do: base_path, else: base_path <> "?" <> q
  end

  defp param_to_string(v) when is_integer(v), do: Integer.to_string(v)
  defp param_to_string(v) when is_atom(v), do: Atom.to_string(v)
  defp param_to_string(v), do: to_string(v)

  @doc """
  Sortable table header: toggles order when the same column is active; otherwise picks a sensible default.
  """
  attr :base_path, :string, required: true
  attr :column, :string, required: true
  attr :label, :string, required: true
  attr :sort, :string, required: true
  attr :order, :string, required: true
  attr :q, :string, required: true
  attr :class, :string, default: nil

  def admin_sort_th(assigns) do
    next_order = next_sort_order(assigns.column, assigns.sort, assigns.order)

    href =
      query_path(assigns.base_path, %{
        page: 1,
        sort: assigns.column,
        order: next_order,
        q: assigns.q
      })

    active = assigns.sort == assigns.column
    indicator = if active, do: sort_arrow(assigns.order), else: ""

    assigns =
      assigns
      |> Phoenix.Component.assign(:href, href)
      |> Phoenix.Component.assign(:active, active)
      |> Phoenix.Component.assign(:indicator, indicator)

    ~H"""
    <th class={["text-left", @class]}>
      <.link
        patch={@href}
        class={["link link-hover text-sm no-underline", @active && "font-semibold"]}
      >
        {@label}{@indicator}
      </.link>
    </th>
    """
  end

  defp sort_arrow("asc"), do: " ▲"
  defp sort_arrow(_), do: " ▼"

  defp next_sort_order(col, cur, ord) do
    if col == cur do
      if ord == "asc", do: "desc", else: "asc"
    else
      default_order_for_column(col)
    end
  end

  defp default_order_for_column("inserted_at"), do: "desc"
  defp default_order_for_column(_), do: "asc"

  attr :base_path, :string, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :total_count, :integer, required: true
  attr :per_page, :integer, required: true
  attr :sort, :string, required: true
  attr :order, :string, required: true
  attr :q, :string, required: true

  def admin_paginator(assigns) do
    page = assigns.page
    total_pages = max(1, assigns.total_pages)
    per = assigns.per_page
    total = assigns.total_count

    start_idx = if total == 0, do: 0, else: (page - 1) * per + 1
    end_idx = min(page * per, total)

    common = %{sort: assigns.sort, order: assigns.order, q: assigns.q}
    first_h = query_path(assigns.base_path, Map.merge(common, %{page: 1}))
    prev_h = query_path(assigns.base_path, Map.merge(common, %{page: max(1, page - 1)}))
    next_h = query_path(assigns.base_path, Map.merge(common, %{page: min(total_pages, page + 1)}))
    last_h = query_path(assigns.base_path, Map.merge(common, %{page: total_pages}))

    window_start = max(1, page - 2)
    window_end = min(total_pages, page + 2)
    window = if total_pages >= 1, do: window_start..window_end//1, else: 1..1//1

    page_links =
      Enum.map(Enum.to_list(window), fn p ->
        {p, query_path(assigns.base_path, Map.merge(common, %{page: p})), p == page}
      end)

    assigns =
      assigns
      |> assign(:start_idx, start_idx)
      |> assign(:end_idx, end_idx)
      |> assign(:first_h, first_h)
      |> assign(:prev_h, prev_h)
      |> assign(:next_h, next_h)
      |> assign(:last_h, last_h)
      |> assign(:page_links, page_links)

    ~H"""
    <div class="flex flex-col gap-3 border-t border-base-300 pt-4 sm:flex-row sm:items-center sm:justify-between">
      <p class="text-sm text-base-content/70">
        <%= if @total_count == 0 do %>
          No rows match.
        <% else %>
          Showing {@start_idx}–{@end_idx} of {@total_count}
        <% end %>
      </p>

      <div :if={@total_pages > 1} class="flex flex-wrap items-center justify-center gap-1">
        <%= if @page <= 1 do %>
          <span class="btn btn-sm btn-ghost pointer-events-none opacity-40">First</span>
          <span class="btn btn-sm btn-ghost pointer-events-none opacity-40">Prev</span>
        <% else %>
          <.link patch={@first_h} class="btn btn-sm">First</.link>
          <.link patch={@prev_h} class="btn btn-sm">Prev</.link>
        <% end %>

        <%= for {p, href, current?} <- @page_links do %>
          <%= if current? do %>
            <span class="btn btn-sm btn-active pointer-events-none">{p}</span>
          <% else %>
            <.link patch={href} class="btn btn-sm btn-ghost">
              {p}
            </.link>
          <% end %>
        <% end %>

        <%= if @page >= @total_pages do %>
          <span class="btn btn-sm btn-ghost pointer-events-none opacity-40">Next</span>
          <span class="btn btn-sm btn-ghost pointer-events-none opacity-40">Last</span>
        <% else %>
          <.link patch={@next_h} class="btn btn-sm">Next</.link>
          <.link patch={@last_h} class="btn btn-sm">Last</.link>
        <% end %>
      </div>
    </div>
    """
  end
end
