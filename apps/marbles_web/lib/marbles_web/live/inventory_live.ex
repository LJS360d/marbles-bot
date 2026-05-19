defmodule MarblesWeb.InventoryLive do
  use MarblesWeb, :live_view

  alias Marbles.Inventory

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] == nil do
      {:ok, redirect(socket, to: ~p"/login")}
    else
      user = socket.assigns.current_user
      items = Inventory.list_user_items(user.id)
      item_metadata = get_item_metadata()

      {:ok,
       socket
       |> assign(:page_title, "Inventory")
       |> assign(:current_scope, :inventory)
       |> assign(:breadcrumbs, [{"Inventory", nil}])
       |> assign(:items, items)
       |> assign(:item_metadata, item_metadata)
       |> assign(:selected_item, nil)
       |> assign(:show_modal, false)}
    end
  end

  @impl true
  def handle_event("select_item", %{"item-type" => item_type, "item-id" => item_id}, socket) do
    selected =
      Enum.find(socket.assigns.items, fn i ->
        i.item_type == item_type && i.item_id == item_id
      end)

    {:noreply,
     socket
     |> assign(:selected_item, selected)
     |> assign(:show_modal, true)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_item, nil)
     |> assign(:show_modal, false)}
  end

  @spec action_type_label(atom()) :: String.t()
  def action_type_label(:get), do: "How to get"
  def action_type_label(:use), do: "How to use"
  def action_type_label(:spend), do: "Where to spend"
  def action_type_label(_), do: "Actions"

  @spec get_item_metadata() :: map()
  defp get_item_metadata do
    Application.get_env(:marbles, :item_metadata, %{})
  end
end

defmodule MarblesWeb.InventoryLive.Helpers do
  @spec get_item_description(String.t(), String.t()) :: String.t()
  def get_item_description(item_type, item_id) do
    item_metadata = Application.get_env(:marbles, :item_metadata, %{})

    case item_metadata do
      %{^item_type => %{^item_id => info}} ->
        Map.get(info, :description, "No description available")

      _ ->
        "No description available"
    end
  end

  @spec get_item_actions(String.t(), String.t(), map()) :: [map()]
  def get_item_actions(item_type, item_id, item_metadata) do
    case item_metadata do
      %{^item_type => %{^item_id => info}} ->
        Map.get(info, :actions, [])

      _ ->
        []
    end
  end
end
