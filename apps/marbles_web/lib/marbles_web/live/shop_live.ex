defmodule MarblesWeb.ShopLive do
  @moduledoc "Public shop — list buyable items, purchase."

  use MarblesWeb, :live_view

  alias Marbles.Economy.Shop

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Shop")
     |> assign(:current_scope, :shop)
     |> assign(:show_login_modal, false)
     |> assign(:products, Shop.products())}
  end

  @impl true
  def handle_event("buy", %{"id" => product_id}, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:noreply, assign(socket, :show_login_modal, true)}

      true ->
        case Shop.buy(user.id, product_id) do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Purchase successful.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Purchase failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      race_state={@race_state}
      current_race_id={@current_race_id}
      current_user={@current_user}
      current_scope={@current_scope}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-6 py-4">
        <h1 class="text-3xl font-bold">Shop</h1>

        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <div
            :for={p <- @products}
            id={"shop-item-#{p.id}"}
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-2"
          >
            <h2 class="font-semibold">{p[:name] || p.id}</h2>
            <p :if={p[:description]} class="text-xs text-base-content/70">{p.description}</p>
            <div class="flex items-center justify-between pt-2">
              <span class="text-sm font-semibold">{p[:price] || p[:cost] || "—"}</span>
              <button
                type="button"
                phx-click="buy"
                phx-value-id={p.id}
                class="btn btn-primary btn-xs"
              >
                Buy
              </button>
            </div>
          </div>
          <div
            :if={@products == []}
            class="col-span-full rounded-2xl border border-base-300 bg-base-200/30 p-6 text-center text-sm text-base-content/60"
          >
            Shop empty.
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
