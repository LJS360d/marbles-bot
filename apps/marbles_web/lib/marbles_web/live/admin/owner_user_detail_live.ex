defmodule MarblesWeb.Admin.OwnerUserDetailLive do
  use MarblesWeb, :live_view
  alias Marbles.Accounts
  alias Marbles.Collection

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Users", ~p"/admin/owner/users"}, {"User", nil}])
     |> assign(:wide, true)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    user = Accounts.get_user!(id)
    {items, total} = Collection.list_user_inventory(user.id, per_page: 50)
    breadcrumbs = [{"Owner", ~p"/admin/owner"}, {"Users", ~p"/admin/owner/users"}, {"User", nil}]

    {:noreply,
     socket
     |> assign(:user, user)
     |> assign(:collection, items)
     |> assign(:collection_total, total)
     |> assign(:breadcrumbs, breadcrumbs)}
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
        <div class="rounded-xl border border-base-300 bg-base-200 p-4">
          <div class="flex items-center justify-between gap-2">
            <div>
              <h1 class="text-xl font-semibold">{Accounts.primary_display_name(@user)}</h1>
              <p :if={@user.display_name} class="text-sm text-base-content/70">{@user.display_name}</p>
              <p class="mt-2 text-sm">
                Role: {@user.role} · Currency: {@user.currency}
              </p>
            </div>
            <.link navigate={~p"/admin/owner/users/#{@user.id}/edit"} class="btn btn-ghost btn-sm">
              Edit
            </.link>
          </div>
          <p :if={@user.identities != []} class="mt-1 text-xs text-base-content/60">
            Identities: <%= Enum.map(@user.identities || [], fn i -> "#{i.platform}: #{i.username}" end) |> Enum.join(", ") %>
          </p>
        </div>
        <section>
          <h2 class="text-lg font-semibold">Collection ({@collection_total})</h2>
          <ul class="mt-2 space-y-2">
            <li
              :for={um <- @collection}
              class="flex items-center justify-between gap-4 rounded-lg border border-base-300 bg-base-100 px-3 py-2"
            >
              <span>{um.marble.name}</span>
              <span class="text-sm text-base-content/70">
                Rarity {um.marble.rarity} · Lv.{um.level}
              </span>
            </li>
          </ul>
          <p :if={@collection == []} class="py-4 text-sm text-base-content/60">No marbles.</p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
