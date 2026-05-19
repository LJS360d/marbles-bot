defmodule MarblesWeb.SquadsLive do
  @moduledoc """
  Squad builder, mining roster assignment, and collection browser.
  """

  use MarblesWeb, :live_view

  alias Marbles.{Assets, Collection}
  alias Marbles.Economy.MineRoster
  alias Marbles.Racing.Squads
  alias Marbles.Schema.UserSquad

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] == nil do
      {:ok, redirect(socket, to: ~p"/login")}
    else
      user = socket.assigns.current_user
      unlock = Squads.ensure_unlock(user.id)
      squads = Squads.list_user_squads(user.id)
      {marbles, total} = Collection.list_user_inventory(user.id, page: 1, per_page: 200)
      mine_marbles = MineRoster.list_assigned_user_marbles(user.id)

      {:ok,
       socket
       |> assign(:page_title, "Roster")
       |> assign(:current_scope, :roster)
       |> assign(:show_login_modal, false)
       |> assign(:breadcrumbs, [{"Roster", nil}])
       |> assign(:max_slots, unlock.max_slots)
       |> assign(:squads, squads)
       |> assign(:collection, marbles)
       |> assign(:collection_total, total)
       |> assign(:mine_marbles, mine_marbles)
       |> assign(:roster_tab, :squads)
       |> assign(:show_marble_modal, false)
       |> assign(:marble_modal, nil)
       |> assign(:preview_texture_url, nil)
       |> reset_editor()}
    end
  end

  @impl true
  def handle_event("new_squad", %{"slot" => slot_str}, socket) do
    slot = String.to_integer(slot_str)

    socket =
      socket
      |> assign(:editing_slot, slot)
      |> assign(:editing_squad, nil)
      |> assign(:editor_name, "Squad #{slot + 1}")
      |> assign(:editor_picks, %{racer_1: nil, racer_2: nil, racer_3: nil, coach: nil})
      |> assign(:editor_role, :racer_1)
      |> with_preview()

    {:noreply, socket}
  end

  def handle_event("edit_squad", %{"squad_id" => id}, socket) do
    case Enum.find(socket.assigns.squads, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      %UserSquad{} = squad ->
        picks =
          squad.slots
          |> Enum.map(fn s -> {s.role, s.user_marble_id} end)
          |> Enum.into(%{racer_1: nil, racer_2: nil, racer_3: nil, coach: nil})

        socket =
          socket
          |> assign(:editing_slot, squad.slot_index)
          |> assign(:editing_squad, squad)
          |> assign(:editor_name, squad.name)
          |> assign(:editor_picks, picks)
          |> assign(:editor_role, :racer_1)
          |> with_preview()

        {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, reset_editor(socket)}

  def handle_event("set_roster_tab", %{"tab" => tab}, socket) do
    tab_atom =
      case tab do
        "squads" -> :squads
        "collection" -> :collection
        _ -> :squads
      end

    {:noreply, assign(socket, :roster_tab, tab_atom)}
  end

  def handle_event("set_role", %{"role" => role_str}, socket) do
    socket =
      socket
      |> assign(:editor_role, String.to_existing_atom(role_str))
      |> with_preview()

    {:noreply, socket}
  end

  def handle_event("name_change", %{"squad" => %{"name" => name}}, socket),
    do: {:noreply, assign(socket, :editor_name, name)}

  def handle_event("pick_marble", %{"user_marble_id" => id}, socket) do
    role = socket.assigns.editor_role

    if marble_matches_role?(socket.assigns.collection, id, role) do
      picks = Map.put(socket.assigns.editor_picks, role, id)
      next_role = first_empty_role(picks)

      socket =
        socket
        |> assign(:editor_picks, picks)
        |> assign(:editor_role, next_role)
        |> with_preview()

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "That marble does not match this slot's role.")}
    end
  end

  def handle_event("clear_pick", %{"role" => role_str}, socket) do
    role = String.to_existing_atom(role_str)

    socket =
      socket
      |> assign(:editor_picks, Map.put(socket.assigns.editor_picks, role, nil))
      |> with_preview()

    {:noreply, socket}
  end

  def handle_event("open_marble_info", %{"user_marble_id" => id}, socket) do
    case find_user_marble(socket, id) do
      nil ->
        {:noreply, socket}

      um ->
        {:noreply,
         socket
         |> assign(:show_marble_modal, true)
         |> assign(:marble_modal, marble_info_payload(um))}
    end
  end

  def handle_event("close_marble_info", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_marble_modal, false)
     |> assign(:marble_modal, nil)}
  end

  def handle_event("add_mine_slot", %{"user_marble_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_mine_slot", %{"user_marble_id" => id}, socket) do
    user = socket.assigns.current_user

    case MineRoster.add_user_marble(user.id, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marble added to mining roster.")
         |> assign(:mine_marbles, MineRoster.list_assigned_user_marbles(user.id))}

      {:error, :roster_full} ->
        {:noreply, put_flash(socket, :error, "Mining roster is full (max 5).")}

      {:error, :already_in_roster} ->
        {:noreply, put_flash(socket, :error, "Already mining that marble.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Marble not found.")}
    end
  end

  def handle_event("remove_mine", %{"user_marble_id" => id}, socket) do
    user = socket.assigns.current_user

    case MineRoster.remove_user_marble(user.id, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:mine_marbles, MineRoster.list_assigned_user_marbles(user.id))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Not in mining roster.")}
    end
  end

  def handle_event("save_squad", _params, socket) do
    user = socket.assigns.current_user
    picks = socket.assigns.editor_picks

    case Squads.upsert(user.id, socket.assigns.editing_slot, socket.assigns.editor_name, picks) do
      {:ok, _squad} ->
        {:noreply,
         socket
         |> put_flash(:info, "Squad saved.")
         |> assign(:squads, Squads.list_user_squads(user.id))
         |> reset_editor()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, save_error(reason))}
    end
  end

  def handle_event("delete_squad", %{"squad_id" => id}, socket) do
    user = socket.assigns.current_user

    case Squads.delete(user.id, id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Squad deleted.")
         |> assign(:squads, Squads.list_user_squads(user.id))
         |> reset_editor()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete squad.")}
    end
  end

  defp find_user_marble(socket, id) do
    Enum.find(socket.assigns.collection, &(&1.id == id)) ||
      Enum.find(socket.assigns.mine_marbles, &(&1.id == id))
  end

  defp marble_matches_role?(collection, user_marble_id, role) do
    case Enum.find(collection, &(&1.id == user_marble_id)) do
      nil ->
        false

      um ->
        um in marbles_for_role(collection, role)
    end
  end

  defp marbles_for_role(collection, role)
       when role in [:racer_1, :racer_2, :racer_3] do
    Enum.filter(collection, fn um ->
      um.marble && um.marble.role == :athlete
    end)
  end

  defp marbles_for_role(collection, :coach) do
    Enum.filter(collection, fn um ->
      m = um.marble

      m &&
        (m.role == :coach ||
           (is_map(um.meta) && Map.get(um.meta, "coach_eligible") == true))
    end)
  end

  defp first_empty_role(picks) do
    [:racer_1, :racer_2, :racer_3, :coach]
    |> Enum.find(fn r -> is_nil(Map.get(picks, r)) end) || :coach
  end

  defp with_preview(socket) do
    url = editor_preview_url(socket.assigns)
    socket = assign(socket, :preview_texture_url, url)
    push_event(socket, "marble:preview", %{texture_url: url || ""})
  end

  defp editor_preview_url(%{editor_picks: picks, editor_role: role, collection: collection}) do
    case Map.get(picks, role) do
      nil ->
        nil

      id ->
        case Enum.find(collection, &(&1.id == id)) do
          %{marble: m} -> Assets.marble_texture_url(m)
          _ -> nil
        end
    end
  end

  defp reset_editor(socket) do
    socket
    |> assign(:editing_slot, nil)
    |> assign(:editing_squad, nil)
    |> assign(:editor_name, "")
    |> assign(:editor_picks, %{racer_1: nil, racer_2: nil, racer_3: nil, coach: nil})
    |> assign(:editor_role, :racer_1)
    |> assign(:show_marble_modal, false)
    |> assign(:marble_modal, nil)
    |> assign(:preview_texture_url, nil)
  end

  defp save_error(:slot_locked), do: "That slot is locked. Unlock more slots first."
  defp save_error(:not_owner), do: "Some of those marbles aren't yours."
  defp save_error(:duplicate_marbles), do: "Each marble can only be in one slot per squad."
  defp save_error(:invalid_coach), do: "Coach slot must be a coach-eligible marble."
  defp save_error(:empty_squad), do: "Pick at least one racer."
  defp save_error(:invalid_role), do: "Unknown squad role."
  defp save_error(other), do: "Could not save: #{inspect(other)}."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :mine_add_options, mine_add_candidates(assigns))

    ~H"""
    <Layouts.app
      flash={@flash}
      race_state={@race_state}
      current_scope={:roster}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <.marble_info_modal
        id="roster-marble-info"
        show={@show_marble_modal}
        marble={@marble_modal}
        on_close="close_marble_info"
      />

      <section class="space-y-6">
        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="text-3xl font-bold">Race Roster</h1>
            <p class="text-sm text-base-content/70">
              {length(@squads)} / {@max_slots} squad slots used.
            </p>
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              phx-click={Phoenix.LiveView.JS.dispatch("phx:race-dock:open")}
              class="btn btn-primary btn-sm rounded-full"
            >
              <.icon name="hero-bolt" class="size-4" /> Quick Race
            </button>
            <.link navigate={~p"/calendar"} class="btn btn-ghost btn-sm rounded-full">
              <.icon name="hero-calendar" class="size-4" /> Calendar
            </.link>
          </div>
        </header>

        <%= if @collection_total == 0 do %>
          <.empty_collection_state />
        <% else %>
          <%= if @editing_slot == nil do %>
            <.mine_section mine_marbles={@mine_marbles} mine_add_options={@mine_add_options} />

            <div class="tabs tabs-boxed w-fit" role="tablist">
              <button
                id="tab-squads"
                role="tab"
                phx-click="set_roster_tab"
                phx-value-tab="squads"
                class={["tab", @roster_tab == :squads && "tab-active"]}
              >
                Squads
              </button>
              <button
                id="tab-collection"
                role="tab"
                phx-click="set_roster_tab"
                phx-value-tab="collection"
                class={["tab", @roster_tab == :collection && "tab-active"]}
              >
                Collection <span class="ml-1 badge badge-sm">{@collection_total}</span>
              </button>
            </div>

            <%= if @roster_tab == :squads do %>
              <.squad_grid squads={@squads} max_slots={@max_slots} />
            <% else %>
              <.collection_grid collection={@collection} />
            <% end %>
          <% else %>
            <.editor
              slot={@editing_slot}
              name={@editor_name}
              role={@editor_role}
              picks={@editor_picks}
              collection={@collection}
              picker_marbles={marbles_for_role(@collection, @editor_role)}
              preview_texture_url={@preview_texture_url}
              squad={@editing_squad}
            />
          <% end %>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp mine_add_candidates(assigns) do
    in_mine = assigns.mine_marbles |> Enum.map(& &1.id) |> MapSet.new()

    Enum.filter(assigns.collection, fn um ->
      not MapSet.member?(in_mine, um.id)
    end)
  end

  attr :mine_marbles, :list, required: true
  attr :mine_add_options, :list, required: true

  defp mine_section(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-300 bg-base-100/60 p-5 backdrop-blur space-y-4">
      <div class="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 class="text-lg font-bold">Mining roster</h2>
          <p class="text-sm text-base-content/60">
            Up to 5 marbles earn passive coins toward your daily claim.
          </p>
        </div>
        <form :if={@mine_add_options != []} phx-change="add_mine_slot" id="mine-add-form">
          <label class="text-xs uppercase tracking-wider text-base-content/60">Add marble</label>
          <select
            name="user_marble_id"
            class="select select-bordered select-sm w-full max-w-xs mt-1"
          >
            <option value="">Choose…</option>
            <option :for={um <- @mine_add_options} value={um.id}>
              {um.marble.name} · Lv.{um.level}
            </option>
          </select>
        </form>
      </div>

      <%= if @mine_marbles == [] do %>
        <p class="text-sm text-base-content/60">No marbles mining yet.</p>
      <% else %>
        <ul class="grid gap-2 sm:grid-cols-2">
          <li
            :for={um <- @mine_marbles}
            class="flex items-center justify-between gap-2 rounded-2xl border border-base-300 bg-base-200/20 px-3 py-2 text-sm"
          >
            <div class="min-w-0">
              <p class="font-medium truncate">{um.marble.name}</p>
              <p class="text-xs text-base-content/60">Lv.{um.level} · ★{um.marble.rarity}</p>
            </div>
            <div class="flex shrink-0 gap-1">
              <button
                type="button"
                phx-click="open_marble_info"
                phx-value-user_marble_id={um.id}
                class="btn btn-ghost btn-xs"
                aria-label="Info"
              >
                <.icon name="hero-information-circle" class="size-4" />
              </button>
              <button
                type="button"
                phx-click="remove_mine"
                phx-value-user_marble_id={um.id}
                class="btn btn-ghost btn-xs text-error"
              >
                Remove
              </button>
            </div>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  defp empty_collection_state(assigns) do
    ~H"""
    <div class="rounded-3xl border border-dashed border-base-300 bg-base-100/40 p-10 text-center">
      <.icon name="hero-cube-transparent" class="size-12 mx-auto opacity-50" />
      <p class="mt-3 text-base-content/70">
        You don't have any marbles yet. Pull on the gacha to start your roster.
      </p>
      <.link navigate={~p"/gacha"} class="btn btn-primary btn-sm rounded-full mt-4">
        <.icon name="hero-gift" class="size-4" /> Open the Gacha
      </.link>
    </div>
    """
  end

  attr :squads, :list, required: true
  attr :max_slots, :integer, required: true

  defp squad_grid(assigns) do
    ~H"""
    <div class="grid gap-5 md:grid-cols-2 lg:grid-cols-3">
      <%= for slot_index <- 0..(@max_slots - 1) do %>
        <% squad = Enum.find(@squads, &(&1.slot_index == slot_index)) %>
        <%= if squad do %>
          <.squad_card squad={squad} />
        <% else %>
          <.squad_empty slot_index={slot_index} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :squad, :any, required: true

  defp squad_card(assigns) do
    ~H"""
    <article class="rounded-3xl border border-base-300 bg-base-100/60 p-5 space-y-3 backdrop-blur">
      <header class="flex items-center justify-between">
        <h3 class="font-semibold">{@squad.name}</h3>
        <span class="badge badge-outline">slot #{@squad.slot_index + 1}</span>
      </header>
      <ul class="space-y-1 text-sm">
        <%= for role <- [:racer_1, :racer_2, :racer_3, :coach] do %>
          <% slot = Enum.find(@squad.slots, &(&1.role == role)) %>
          <li class="flex items-center justify-between gap-2">
            <span class="text-base-content/60">{role_label(role)}</span>
            <span class="font-medium truncate text-base-content/80">
              <%= if slot && slot.user_marble && slot.user_marble.marble do %>
                {slot.user_marble.marble.name}
              <% else %>
                <span class="text-base-content/40">—</span>
              <% end %>
            </span>
          </li>
        <% end %>
      </ul>
      <div class="flex justify-between pt-2">
        <button
          type="button"
          phx-click="edit_squad"
          phx-value-squad_id={@squad.id}
          id={"edit-squad-#{@squad.id}"}
          class="btn btn-ghost btn-xs"
        >
          Edit
        </button>
        <button
          type="button"
          phx-click="delete_squad"
          phx-value-squad_id={@squad.id}
          data-confirm="Delete this squad?"
          id={"delete-squad-#{@squad.id}"}
          class="btn btn-ghost btn-xs text-error"
        >
          Delete
        </button>
      </div>
    </article>
    """
  end

  attr :slot_index, :integer, required: true

  defp squad_empty(assigns) do
    ~H"""
    <article class="rounded-3xl border border-dashed border-base-300 bg-base-100/40 p-5 text-center space-y-3">
      <p class="text-base-content/60">Slot #{@slot_index + 1}</p>
      <button
        type="button"
        phx-click="new_squad"
        phx-value-slot={@slot_index}
        id={"new-squad-#{@slot_index}"}
        class="btn btn-primary btn-sm rounded-full"
      >
        <.icon name="hero-plus" class="size-4" /> New squad
      </button>
    </article>
    """
  end

  attr :collection, :list, required: true

  defp collection_grid(assigns) do
    ~H"""
    <div id="collection-grid" class="grid gap-3 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
      <%= for um <- @collection do %>
        <article
          id={"coll-card-#{um.id}"}
          class="group rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur overflow-hidden flex flex-col"
        >
          <%!-- Texture thumbnail --%>
          <div class="relative h-24 bg-base-200/60 flex items-center justify-center overflow-hidden">
            <%= if texture_url = marble_card_texture_url(um) do %>
              <img
                src={texture_url}
                alt={um.marble.name}
                class="h-full w-full object-contain group-hover:scale-105 transition-transform duration-200"
              />
            <% else %>
              <.rarity_orb rarity={um.marble.rarity} />
            <% end %>
            <span class="absolute top-1.5 right-1.5 badge badge-xs badge-neutral opacity-80">
              ★{um.marble.rarity}
            </span>
          </div>

          <%!-- Info row --%>
          <div class="flex items-center justify-between gap-2 px-3 py-2">
            <div class="min-w-0">
              <p class="font-semibold text-sm truncate">{um.marble.name}</p>
              <p class="text-[11px] text-base-content/60">
                {role_label_short(um.marble.role)} · Lv.{um.level}
              </p>
            </div>
            <button
              type="button"
              phx-click="open_marble_info"
              phx-value-user_marble_id={um.id}
              id={"coll-info-#{um.id}"}
              class="btn btn-ghost btn-xs shrink-0"
              aria-label="Marble details"
            >
              <.icon name="hero-information-circle" class="size-4" />
            </button>
          </div>
        </article>
      <% end %>
    </div>
    """
  end

  attr :rarity, :integer, required: true

  defp rarity_orb(assigns) do
    color =
      case assigns.rarity do
        r when r >= 5 -> "from-yellow-400 to-orange-500"
        4 -> "from-purple-400 to-indigo-500"
        3 -> "from-blue-400 to-cyan-500"
        _ -> "from-slate-400 to-slate-600"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <div class={["size-12 rounded-full bg-linear-to-br opacity-80", @color]} />
    """
  end

  defp marble_card_texture_url(%{marble: marble}) do
    Assets.marble_texture_url(marble)
  end

  defp role_label_short(nil), do: "—"
  defp role_label_short(:athlete), do: "Racer"
  defp role_label_short(:coach), do: "Coach"
  defp role_label_short(r) when is_atom(r), do: r |> Atom.to_string() |> String.capitalize()
  defp role_label_short(r) when is_binary(r), do: String.capitalize(r)

  defp role_label(:racer_1), do: "Racer 1"
  defp role_label(:racer_2), do: "Racer 2"
  defp role_label(:racer_3), do: "Racer 3"
  defp role_label(:coach), do: "Coach"

  attr :slot, :integer, required: true
  attr :name, :string, required: true
  attr :role, :atom, required: true
  attr :picks, :map, required: true
  attr :collection, :list, required: true
  attr :picker_marbles, :list, required: true
  attr :preview_texture_url, :any, default: nil
  attr :squad, :any, default: nil

  defp editor(assigns) do
    ~H"""
    <section class="space-y-4">
      <header class="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 class="text-2xl font-bold">
            Slot #{@slot + 1} {if @squad, do: "· editing", else: "· new"}
          </h2>
          <p class="text-sm text-base-content/60">
            Racers must be athlete-role marbles. Coach accepts coach role or coach-eligible collection entries.
          </p>
        </div>
        <div class="flex gap-2">
          <button type="button" phx-click="cancel_edit" id="cancel-edit" class="btn btn-ghost btn-sm">
            Cancel
          </button>
          <button
            type="button"
            phx-click="save_squad"
            id="save-squad"
            class="btn btn-primary btn-sm rounded-full"
          >
            Save squad
          </button>
        </div>
      </header>

      <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_280px]">
        <div class="space-y-4">
          <form phx-change="name_change">
            <input
              type="text"
              name="squad[name]"
              value={@name}
              maxlength="64"
              class="input input-bordered w-full max-w-md"
              placeholder="Squad name"
            />
          </form>

          <div class="flex flex-wrap gap-2">
            <%= for role <- [:racer_1, :racer_2, :racer_3, :coach] do %>
              <button
                type="button"
                phx-click="set_role"
                phx-value-role={Atom.to_string(role)}
                id={"role-pill-#{role}"}
                class={[
                  "rounded-full border px-3 py-1 text-sm transition",
                  @role == role && "border-primary bg-primary/10",
                  @role != role && "border-base-300 hover:bg-base-200/40"
                ]}
              >
                {role_label(role)}
                <span :if={pick = Map.get(@picks, role)} class="ml-1 text-xs text-base-content/50">
                  · {pick_summary(pick, @collection)}
                </span>
              </button>
            <% end %>
          </div>

          <div class="flex flex-wrap gap-3">
            <%= for {role, pick} <- @picks do %>
              <div class="rounded-2xl border border-base-300 bg-base-100/40 px-4 py-2 text-sm">
                <span class="text-base-content/60">{role_label(role)}:</span>
                <span class="font-medium">{pick_summary(pick, @collection)}</span>
                <button
                  :if={pick}
                  type="button"
                  phx-click="clear_pick"
                  phx-value-role={Atom.to_string(role)}
                  id={"clear-#{role}"}
                  class="btn btn-ghost btn-xs ml-2"
                >
                  Clear
                </button>
              </div>
            <% end %>
          </div>

          <div class="rounded-3xl border border-base-300 bg-base-100/60 p-4 backdrop-blur">
            <p class="text-xs uppercase tracking-[0.3em] text-base-content/60 mb-3">
              {role_label(@role)} picks ({length(@picker_marbles)} available)
            </p>
            <ul class="grid gap-2 sm:grid-cols-2">
              <li :for={um <- @picker_marbles}>
                <div class="flex gap-1 rounded-2xl border border-base-300 bg-base-100/40 p-1">
                  <button
                    type="button"
                    phx-click="pick_marble"
                    phx-value-user_marble_id={um.id}
                    id={"pick-#{um.id}"}
                    class={[
                      "flex-1 rounded-xl px-2 py-1.5 text-left text-sm transition flex items-center gap-2",
                      pick_used?(um.id, @picks) && "bg-primary/15",
                      not pick_used?(um.id, @picks) && "hover:bg-base-200/40"
                    ]}
                  >
                    <%!-- Inline texture thumbnail --%>
                    <%= if thumb = marble_card_texture_url(um) do %>
                      <img
                        src={thumb}
                        alt=""
                        class="size-9 rounded-lg object-contain shrink-0 bg-base-200/60"
                      />
                    <% else %>
                      <div class="size-9 rounded-lg bg-base-200/60 shrink-0 flex items-center justify-center text-xs font-bold text-base-content/40">
                        ★{um.marble.rarity}
                      </div>
                    <% end %>
                    <div class="min-w-0">
                      <div class="flex items-center justify-between gap-1">
                        <span class="font-medium truncate">{um.marble.name}</span>
                        <span class="badge badge-xs badge-outline shrink-0">★{um.marble.rarity}</span>
                      </div>
                      <p class="text-xs text-base-content/60">Lv. {um.level}</p>
                    </div>
                  </button>
                  <button
                    type="button"
                    phx-click="open_marble_info"
                    phx-value-user_marble_id={um.id}
                    class="btn btn-ghost btn-sm px-2"
                    aria-label="Marble info"
                  >
                    <.icon name="hero-information-circle" class="size-4" />
                  </button>
                </div>
              </li>
            </ul>
          </div>
        </div>

        <div class="space-y-2">
          <p class="text-xs uppercase tracking-wider text-base-content/60">Selected preview</p>
          <div
            id="roster-marble-preview"
            phx-hook="MarblePreview"
            phx-update="ignore"
            data-texture-url={@preview_texture_url || ""}
            class="h-56 w-full rounded-2xl border border-base-300 bg-black"
          />
        </div>
      </div>
    </section>
    """
  end

  defp pick_used?(id, picks), do: id in Map.values(picks)

  defp pick_summary(nil, _collection), do: "—"

  defp pick_summary(id, collection) do
    case Enum.find(collection, &(&1.id == id)) do
      nil -> "—"
      um -> um.marble.name
    end
  end
end
