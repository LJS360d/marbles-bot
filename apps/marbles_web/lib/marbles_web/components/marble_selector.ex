defmodule MarblesWeb.Components.MarbleSelector do
  @moduledoc """
  Marble multi-select LiveComponent with search, rarity/team filters, and bulk actions.

  The parent LiveView owns the selection list (`selected_ids`). On every change the
  component sends `{:marble_selection_changed, new_ids}` to the parent so it can
  update its own assign and pass the new list back as `selected_ids`.

  ## Usage

      <.live_component
        module={MarblesWeb.Components.MarbleSelector}
        id="marble-selector"
        selected_ids={@marble_ids}
      />

  Parent LiveView must implement:

      @impl true
      def handle_info({:marble_selection_changed, ids}, socket) do
        {:noreply, assign(socket, :marble_ids, ids)}
      end
  """

  use MarblesWeb, :live_component
  alias Marbles.Catalog

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:marble_search, fn -> "" end)
      |> assign_new(:marble_filter_team_id, fn -> nil end)
      |> assign_new(:marble_filter_rarity, fn -> nil end)
      |> assign_new(:marbles, fn -> Catalog.list_marbles(per_page: 500) |> elem(0) end)
      |> assign_new(:teams, fn -> Catalog.list_teams() end)

    filtered =
      apply_filters(
        socket.assigns.marbles,
        socket.assigns.marble_search,
        socket.assigns.marble_filter_team_id,
        socket.assigns.marble_filter_rarity
      )

    {:ok, assign(socket, :filtered_marbles, filtered)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("toggle_marble", %{"id" => id}, socket) do
    ids = socket.assigns.selected_ids
    new_ids = if id in ids, do: List.delete(ids, id), else: [id | ids]
    send(self(), {:marble_selection_changed, new_ids})
    {:noreply, assign(socket, :selected_ids, new_ids)}
  end

  def handle_event("marble_filter", params, socket) do
    q = Map.get(params, "q", "") || ""

    team_id =
      case params["team_id"] do
        "" -> nil
        id -> id
      end

    rarity =
      case params["rarity"] do
        "" -> nil
        r -> String.to_integer(r)
      end

    filtered = apply_filters(socket.assigns.marbles, q, team_id, rarity)

    {:noreply,
     socket
     |> assign(:marble_search, q)
     |> assign(:marble_filter_team_id, team_id)
     |> assign(:marble_filter_rarity, rarity)
     |> assign(:filtered_marbles, filtered)}
  end

  def handle_event("select_all_shown", _params, socket) do
    ids = Enum.map(socket.assigns.filtered_marbles, & &1.id)
    new_ids = Enum.uniq(ids ++ socket.assigns.selected_ids)
    send(self(), {:marble_selection_changed, new_ids})
    {:noreply, assign(socket, :selected_ids, new_ids)}
  end

  def handle_event("deselect_all_shown", _params, socket) do
    remove_ids = MapSet.new(Enum.map(socket.assigns.filtered_marbles, & &1.id))
    new_ids = Enum.reject(socket.assigns.selected_ids, &(&1 in remove_ids))
    send(self(), {:marble_selection_changed, new_ids})
    {:noreply, assign(socket, :selected_ids, new_ids)}
  end

  def handle_event("select_all_team", %{"team_id" => team_id}, socket) do
    team_ids =
      socket.assigns.marbles |> Enum.filter(&(&1.team_id == team_id)) |> Enum.map(& &1.id)

    new_ids = Enum.uniq((socket.assigns.selected_ids || []) ++ team_ids)
    send(self(), {:marble_selection_changed, new_ids})
    {:noreply, assign(socket, :selected_ids, new_ids)}
  end

  def handle_event("deselect_all_team", %{"team_id" => team_id}, socket) do
    remove_ids =
      socket.assigns.marbles
      |> Enum.filter(&(&1.team_id == team_id))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    new_ids = Enum.reject(socket.assigns.selected_ids, &(&1 in remove_ids))
    send(self(), {:marble_selection_changed, new_ids})
    {:noreply, assign(socket, :selected_ids, new_ids)}
  end

  @spec apply_filters([map()], String.t(), String.t() | nil, integer() | nil) :: [map()]
  defp apply_filters(marbles, search, team_id, rarity) do
    Enum.filter(marbles, fn m ->
      (search == "" or String.contains?(String.downcase(m.name), String.downcase(search))) and
        (is_nil(team_id) or (m.team_id && m.team_id == team_id)) and
        (is_nil(rarity) or m.rarity == rarity)
    end)
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="fieldset border-t border-base-300 pt-6 mt-6" id={"#{@id}-fieldset"}>
      <span class="label mb-1">Marbles in pack</span>
      <p class="text-sm text-base-content/70 mb-2">
        {length(@selected_ids)} selected. Search and filter below, or use quick actions.
      </p>
      <form
        phx-change="marble_filter"
        phx-target={@myself}
        id={"#{@id}-filter-form"}
        class="flex flex-wrap items-center gap-2 mb-2"
      >
        <input
          type="text"
          name="q"
          value={@marble_search}
          phx-debounce="150"
          placeholder="Search by name..."
          class="input input-bordered input-sm w-44"
        />
        <select name="team_id" class="select select-bordered select-sm w-44">
          <option value="">All teams</option>
          <option :for={t <- @teams} value={t.id} selected={@marble_filter_team_id == t.id}>
            {t.name}
          </option>
        </select>
        <select name="rarity" class="select select-bordered select-sm w-28">
          <option value="">All rarities</option>
          <option value="1" selected={@marble_filter_rarity == 1}>R1</option>
          <option value="2" selected={@marble_filter_rarity == 2}>R2</option>
          <option value="3" selected={@marble_filter_rarity == 3}>R3</option>
        </select>
        <button
          type="button"
          phx-click="select_all_shown"
          phx-target={@myself}
          class="btn btn-ghost btn-sm"
        >
          Select all shown
        </button>
        <button
          type="button"
          phx-click="deselect_all_shown"
          phx-target={@myself}
          class="btn btn-ghost btn-sm"
        >
          Deselect all shown
        </button>
        <div class="dropdown dropdown-end">
          <label tabindex="0" class="btn btn-ghost btn-sm">Add whole team</label>
          <ul
            tabindex="0"
            class="dropdown-content menu z-10 rounded-box bg-base-200 p-2 shadow min-w-56 max-h-72 overflow-y-auto text-sm"
          >
            <li :for={t <- @teams}>
              <button
                type="button"
                phx-click="select_all_team"
                phx-value-team_id={t.id}
                phx-target={@myself}
                class="py-2 px-3"
              >
                {t.name}
              </button>
            </li>
          </ul>
        </div>
        <div class="dropdown dropdown-end">
          <label tabindex="0" class="btn btn-ghost btn-sm">Remove whole team</label>
          <ul
            tabindex="0"
            class="dropdown-content menu z-10 rounded-box bg-base-200 p-2 shadow min-w-56 max-h-72 overflow-y-auto text-sm"
          >
            <li :for={t <- @teams}>
              <button
                type="button"
                phx-click="deselect_all_team"
                phx-value-team_id={t.id}
                phx-target={@myself}
                class="py-2 px-3"
              >
                {t.name}
              </button>
            </li>
          </ul>
        </div>
      </form>
      <div class="max-h-[min(28rem,72vh)] overflow-y-auto rounded border border-base-300 p-2">
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
          <%= for m <- @filtered_marbles do %>
            <label
              for={"#{@id}-marble-#{m.id}"}
              class={[
                "flex min-h-20 cursor-pointer flex-col gap-1 rounded-lg border px-2 py-2 text-left transition",
                "hover:border-primary/40 hover:bg-base-200/70",
                if(m.id in @selected_ids,
                  do: "border-primary bg-primary/10",
                  else: "border-base-300 bg-base-100"
                )
              ]}
            >
              <div class="flex items-start gap-2">
                <input
                  type="checkbox"
                  id={"#{@id}-marble-#{m.id}"}
                  value={m.id}
                  checked={m.id in @selected_ids}
                  phx-click="toggle_marble"
                  phx-value-id={m.id}
                  phx-target={@myself}
                  class="mt-0.5 shrink-0"
                />
                <span class="line-clamp-2 text-sm font-medium leading-snug">{m.name}</span>
              </div>
              <span class="pl-6 text-[11px] text-base-content/55 tabular-nums">R{m.rarity}</span>
              <span :if={m.team} class="pl-6 text-[11px] text-base-content/45 line-clamp-1">
                {m.team.name}
              </span>
            </label>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
