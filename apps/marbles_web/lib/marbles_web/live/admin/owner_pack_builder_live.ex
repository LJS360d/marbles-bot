defmodule MarblesWeb.Admin.OwnerPackBuilderLive do
  use MarblesWeb, :live_view
  alias Marbles.Packs
  alias Marbles.Catalog
  alias Marbles.Repo
  alias Marbles.Schema.Pack

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Pack")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Packs", ~p"/admin/owner/packs"}, {"Pack", nil}])
     |> assign(:wide, true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case params["id"] do
        nil ->
          form = %Pack{} |> Pack.changeset(%{}) |> to_form(as: "pack")
          assign(socket, pack: nil, form: form, marble_ids: [])

        id ->
          pack = Packs.get_pack!(id)
          marble_ids = Enum.map(pack.marbles || [], & &1.id)

          form =
            pack
            |> Pack.changeset(%{
              name: pack.name,
              description: pack.description,
              cost: pack.cost,
              active: pack.active,
              start_date: pack.start_date,
              end_date: pack.end_date,
              banner_path: pack.banner_path
            })
            |> to_form(as: "pack")

          assign(socket, pack: pack, form: form, marble_ids: marble_ids)
      end

    marbles = Catalog.list_marbles(per_page: 500) |> elem(0)
    {:noreply, assign(socket, marbles: marbles)}
  end

  @impl true
  def handle_event("validate", %{"pack" => params}, socket) do
    changeset =
      (socket.assigns.pack || %Pack{})
      |> Pack.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "pack"))}
  end

  @impl true
  def handle_event("save", %{"pack" => params}, socket) do
    marble_ids = socket.assigns.marble_ids || []

    result =
      if socket.assigns.pack do
        socket.assigns.pack
        |> Pack.changeset(params)
        |> Repo.update()
        |> case do
          {:ok, pack} -> Packs.set_pack_marbles(pack, marble_ids)
          err -> err
        end
      else
        case Packs.create_pack(params) do
          {:ok, pack} -> Packs.set_pack_marbles(pack, marble_ids)
          err -> err
        end
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pack saved.")
         |> push_navigate(to: ~p"/admin/owner/packs")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "pack"))}
    end
  end

  @impl true
  def handle_event("toggle_marble", %{"id" => id}, socket) do
    ids = socket.assigns.marble_ids

    marble_ids =
      if id in ids do
        List.delete(ids, id)
      else
        [id | ids]
      end

    {:noreply, assign(socket, marble_ids: marble_ids)}
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
        <h1 class="text-2xl font-semibold">{if @pack, do: "Edit pack", else: "New pack"}</h1>

        <.form
          for={@form}
          id="pack-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <.input field={@form[:cost]} type="number" label="Cost" />
          <.input field={@form[:banner_path]} type="text" label="Banner path" />
          <.input field={@form[:active]} type="checkbox" label="Active" />
          <.input field={@form[:start_date]} type="date" label="Start date" />
          <.input field={@form[:end_date]} type="date" label="End date" />

          <div class="fieldset">
            <span class="label mb-1">Marbles in pack</span>
            <p class="text-sm text-base-content/70 mb-2">
              Select marbles to include. ({length(@marble_ids)} selected)
            </p>
            <div class="max-h-48 overflow-y-auto rounded border border-base-300 p-2 space-y-1">
              <%= for m <- @marbles do %>
                <label
                  for={"marble-#{m.id}"}
                  class="flex items-center gap-2 cursor-pointer rounded px-2 py-1 hover:bg-base-200"
                >
                  <input
                    type="checkbox"
                    id={"marble-#{m.id}"}
                    value={m.id}
                    checked={m.id in @marble_ids}
                    phx-click="toggle_marble"
                    phx-value-id={m.id}
                  />
                  <span>{m.name}</span>
                  <span class="text-xs text-base-content/60">R{m.rarity}</span>
                </label>
              <% end %>
            </div>
          </div>

          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <.link navigate={~p"/admin/owner/packs"} class="btn btn-ghost">Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
