defmodule MarblesWeb.RosterLive do
  @moduledoc """
  Squad builder. Lists all squads owned by the user (up to their unlocked
  slot count) and provides a per-slot editor that picks 3 racers + 1 coach
  from the user's `user_marbles` collection.

  When the user has zero marbles, shows an empty state with a CTA to the
  gacha.
  """

  use MarblesWeb, :live_view

  alias Marbles.Collection
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
       |> reset_editor()}
    end
  end

  @impl true
  def handle_event("new_squad", %{"slot" => slot_str}, socket) do
    slot = String.to_integer(slot_str)

    {:noreply,
     socket
     |> assign(:editing_slot, slot)
     |> assign(:editing_squad, nil)
     |> assign(:editor_name, "Squad #{slot + 1}")
     |> assign(:editor_picks, %{racer_1: nil, racer_2: nil, racer_3: nil, coach: nil})
     |> assign(:editor_role, :racer_1)}
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

        {:noreply,
         socket
         |> assign(:editing_slot, squad.slot_index)
         |> assign(:editing_squad, squad)
         |> assign(:editor_name, squad.name)
         |> assign(:editor_picks, picks)
         |> assign(:editor_role, :racer_1)}
    end
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, reset_editor(socket)}

  def handle_event("set_role", %{"role" => role_str}, socket) do
    {:noreply, assign(socket, :editor_role, String.to_existing_atom(role_str))}
  end

  def handle_event("name_change", %{"squad" => %{"name" => name}}, socket),
    do: {:noreply, assign(socket, :editor_name, name)}

  def handle_event("pick_marble", %{"user_marble_id" => id}, socket) do
    role = socket.assigns.editor_role
    picks = Map.put(socket.assigns.editor_picks, role, id)
    {:noreply, assign(socket, :editor_picks, picks)}
  end

  def handle_event("clear_pick", %{"role" => role_str}, socket) do
    role = String.to_existing_atom(role_str)
    picks = Map.put(socket.assigns.editor_picks, role, nil)
    {:noreply, assign(socket, :editor_picks, picks)}
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

  defp reset_editor(socket) do
    socket
    |> assign(:editing_slot, nil)
    |> assign(:editing_squad, nil)
    |> assign(:editor_name, "")
    |> assign(:editor_picks, %{racer_1: nil, racer_2: nil, racer_3: nil, coach: nil})
    |> assign(:editor_role, :racer_1)
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
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={:roster}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
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
          <%= if @editing_slot do %>
            <.editor
              slot={@editing_slot}
              name={@editor_name}
              role={@editor_role}
              picks={@editor_picks}
              collection={@collection}
              squad={@editing_squad}
            />
          <% else %>
            <.squad_grid squads={@squads} max_slots={@max_slots} />
          <% end %>
        <% end %>
      </section>
    </Layouts.app>
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

  defp role_label(:racer_1), do: "Racer 1"
  defp role_label(:racer_2), do: "Racer 2"
  defp role_label(:racer_3), do: "Racer 3"
  defp role_label(:coach), do: "Coach"

  attr :slot, :integer, required: true
  attr :name, :string, required: true
  attr :role, :atom, required: true
  attr :picks, :map, required: true
  attr :collection, :list, required: true
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
            Pick 1–3 racers. Coach is optional but enables coach abilities and team-signature stacking.
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
          Collection ({length(@collection)})
        </p>
        <ul class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          <li :for={um <- @collection}>
            <button
              type="button"
              phx-click="pick_marble"
              phx-value-user_marble_id={um.id}
              id={"pick-#{um.id}"}
              class={[
                "w-full rounded-2xl border px-4 py-2 text-left transition",
                pick_used?(um.id, @picks) && "border-primary bg-primary/10",
                not pick_used?(um.id, @picks) && "border-base-300 hover:bg-base-200/40"
              ]}
            >
              <div class="flex items-center justify-between">
                <span class="font-medium truncate">{um.marble.name}</span>
                <span class="badge badge-sm badge-outline">★{um.marble.rarity}</span>
              </div>
              <p class="text-xs text-base-content/60 mt-1">
                Lv. {um.level} · {role_label_or(um.marble.role)}
              </p>
            </button>
          </li>
        </ul>
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

  defp role_label_or(nil), do: "—"
  defp role_label_or(role) when is_atom(role), do: Atom.to_string(role)
end
