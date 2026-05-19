defmodule MarblesWeb.UpgradeMarbleLive do
  use MarblesWeb, :live_view

  alias Marbles.{Collection, Inventory, MarbleUpgrades}

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] == nil do
      {:ok, redirect(socket, to: ~p"/login")}
    else
      user = socket.assigns.current_user
      {marbles, _} = Collection.list_user_inventory(user.id, page: 1, per_page: 200)

      three_stars =
        Enum.filter(marbles, fn um ->
          marble = um.marble
          (marble.rarity || 1) == 3
        end)

      marble_cores = Inventory.get_item_quantity(user.id, "material", "marble_core")

      {:ok,
       socket
       |> assign(:page_title, "Upgrade Marble")
       |> assign(:current_scope, :upgrade_marble)
       |> assign(:breadcrumbs, [{"Upgrade Marble", nil}])
       |> assign(:three_stars, three_stars)
       |> assign(:marble_cores, marble_cores)
       |> assign(:selected_marble, nil)
       |> assign(:show_modal, false)
       |> assign(:upgrade_error, nil)
       |> assign(:upgrade_success, false)}
    end
  end

  @impl true
  def handle_event("select_marble", %{"user_marble_id" => id}, socket) do
    selected = Enum.find(socket.assigns.three_stars, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_marble, selected)
     |> assign(:show_modal, true)
     |> assign(:upgrade_error, nil)
     |> assign(:upgrade_success, false)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_marble, nil)
     |> assign(:show_modal, false)
     |> assign(:upgrade_error, nil)
     |> assign(:upgrade_success, false)}
  end

  def handle_event("upgrade", _params, socket) do
    user = socket.assigns.current_user
    selected = socket.assigns.selected_marble

    case MarbleUpgrades.apply_marble_core(user.id, selected.id) do
      {:ok, upgraded_marble} ->
        {:noreply,
         socket
         |> assign(:upgrade_success, true)
         |> assign(:selected_marble, upgraded_marble)
         |> assign(:upgrade_error, nil)}

      {:error, :insufficient_marble_core} ->
        {:noreply,
         socket
         |> assign(:upgrade_error, "You don't have any marble cores!")}

      {:error, :not_3_star} ->
        {:noreply,
         socket
         |> assign(:upgrade_error, "This marble is not 3-star!")}

      {:error, :core_already_applied} ->
        {:noreply,
         socket
         |> assign(:upgrade_error, "A marble core has already been applied to this marble!")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:upgrade_error, "An error occurred during upgrade")}
    end
  end
end
