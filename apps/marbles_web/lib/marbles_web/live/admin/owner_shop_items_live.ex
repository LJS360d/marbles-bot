defmodule MarblesWeb.Admin.OwnerShopItemsLive do
  use MarblesWeb, :live_view
  alias Marbles.Economy.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Shop items")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Economy", ~p"/admin/owner/economy"},
       {"Shop items", nil}
     ])
     |> load_items()}
  end

  @impl true
  def handle_event("save_item", %{"item" => params}, socket) do
    id = params["id"]

    attrs = %{
      enabled: params["enabled"] == "true",
      coin_price: parse_int_or_nil(params["coin_price"]),
      dust_price: parse_int_or_nil(params["dust_price"]),
      duration_sec: parse_int_or_nil(params["duration_sec"]),
      limit_count: parse_int_or_nil(params["limit_count"]),
      limit_period_unit: empty_to_nil(params["limit_period_unit"]),
      label_override: empty_to_nil(params["label_override"])
    }

    case Admin.upsert_shop_item(id, attrs) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Saved #{id}.") |> load_items()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not save #{id}: #{inspect(changeset.errors)}")
         |> load_items()}
    end
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
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h1 class="text-2xl font-semibold">Shop items</h1>
          <.link navigate={~p"/admin/owner/economy"} class="btn btn-ghost btn-sm">
            Back to economy
          </.link>
        </div>

        <p class="text-sm text-base-content/70">
          Overrides are stored in DB and applied immediately to `/shop`.
        </p>

        <div class="space-y-4">
          <article
            :for={item <- @items}
            class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm"
          >
            <.form
              for={%{}}
              as={:item}
              id={"shop-item-#{item.id}"}
              phx-submit="save_item"
              class="space-y-3"
            >
              <input type="hidden" name="item[id]" value={item.id} />
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h2 class="font-semibold">{item.base_name}</h2>
                  <p class="text-xs text-base-content/70">{item.id}</p>
                </div>
                <label class="flex items-center gap-2 text-sm">
                  <span>Enabled</span>
                  <select name="item[enabled]" class="select select-bordered select-sm">
                    <option value="true" selected={item.enabled}>true</option>
                    <option value="false" selected={!item.enabled}>false</option>
                  </select>
                </label>
              </div>
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-6">
                <.input
                  name="item[label_override]"
                  value={item.name}
                  label="Label override"
                  type="text"
                />
                <.input name="item[coin_price]" value={item.coin} label="Coin price" type="number" />
                <.input name="item[dust_price]" value={item.dust} label="Dust price" type="number" />
                <.input
                  name="item[duration_sec]"
                  value={item.duration_sec}
                  label="Duration seconds"
                  type="number"
                />
                <.input
                  name="item[limit_count]"
                  value={item.limit_count}
                  label="Limit count"
                  type="number"
                />
                <.input
                  name="item[limit_period_unit]"
                  value={item.limit_period_unit}
                  label="Limit period (day|week|month)"
                  type="text"
                />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Save overrides</button>
            </.form>
          </article>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_items(socket), do: assign(socket, :items, Admin.list_shop_items())

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(""), do: nil

  defp parse_int_or_nil(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(v), do: v
end
