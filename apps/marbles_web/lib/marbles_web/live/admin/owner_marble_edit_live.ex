defmodule MarblesWeb.Admin.OwnerMarbleEditLive do
  use MarblesWeb, :live_view
  alias Marbles.Catalog
  alias Marbles.Schema.Marble

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Edit marble")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Marbles", ~p"/admin/owner/marbles"},
       {"Edit", nil}
     ])
     |> assign(:wide, true)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    marble = Catalog.get_marble!(id)
    teams = Catalog.list_teams()

    form =
      marble
      |> Marble.changeset(%{})
      |> to_form(as: "marble")

    {:noreply,
     socket
     |> assign(:marble, marble)
     |> assign(:teams, teams)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"marble" => params}, socket) do
    params = parse_base_stats(params)

    changeset =
      socket.assigns.marble
      |> Marble.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "marble"))}
  end

  @impl true
  def handle_event("save", %{"marble" => params}, socket) do
    params = parse_base_stats(params)

    case Catalog.update_marble(socket.assigns.marble, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marble updated.")
         |> push_navigate(to: ~p"/admin/owner/marbles")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "marble"))}
    end
  end

  defp parse_base_stats(params) do
    str = params["base_stats_json"]
    params = Map.delete(params, "base_stats_json")

    base_stats =
      cond do
        str == nil or str == "" ->
          %{}

        true ->
          case Jason.decode(str) do
            {:ok, map} when is_map(map) -> map
            _ -> params["base_stats"] || %{}
          end
      end

    Map.put(params, "base_stats", base_stats)
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
        <h1 class="text-2xl font-semibold">Edit {@marble.name}</h1>

        <.form
          for={@form}
          id="marble-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:edition]} type="text" label="Edition" />
          <.input
            field={@form[:role]}
            type="select"
            label="Role"
            options={[Athlete: "athlete", Coach: "coach", Support: "support", Manager: "manager"]}
          />
          <.input field={@form[:rarity]} type="number" label="Rarity" />
          <.input
            field={@form[:team_id]}
            type="select"
            label="Team"
            prompt="None"
            options={Enum.map(@teams, fn t -> {t.name, t.id} end)}
            value={@form[:team_id].value}
          />
          <div class="fieldset mb-2">
            <label for="marble_base_stats_json">
              <span class="label mb-1">Base stats (JSON)</span>
              <textarea
                id="marble_base_stats_json"
                name="marble[base_stats_json]"
                class="w-full textarea textarea-bordered h-24 font-mono text-sm"
              >{Jason.encode!(@marble.base_stats || %{})}</textarea>
            </label>
          </div>
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <.link navigate={~p"/admin/owner/marbles"} class="btn btn-ghost">Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
