defmodule MarblesWeb.Admin.OwnerTeamsLive do
  use MarblesWeb, :live_view
  alias Marbles.Catalog
  alias Marbles.Schema.Team

  @impl true
  def mount(_params, _session, socket) do
    teams = Catalog.list_teams()

    {:ok,
     socket
     |> assign(:page_title, "Teams")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Teams", nil}])
     |> assign(:teams, teams)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("new_team", _params, socket) do
    form = %Team{} |> Team.changeset(%{}) |> to_form(as: "team")
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("validate_team", %{"team" => params}, socket) do
    changeset =
      %Team{}
      |> Team.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "team"))}
  end

  @impl true
  def handle_event("save_team", %{"team" => params}, socket) do
    case Catalog.create_team(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Team created.")
         |> assign(:teams, Catalog.list_teams())
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "team"))}
    end
  end

  @impl true
  def handle_event("cancel_team", _params, socket) do
    {:noreply, assign(socket, form: nil)}
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
        <h1 class="text-2xl font-semibold">Teams</h1>

        <div class="overflow-x-auto rounded-xl border border-base-300">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Name</th>
                <th>Logo path</th>
                <th>Color</th>
                <th class="w-0">Edit</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={t <- @teams}>
                <td>{t.name}</td>
                <td>{t.logo_path || "—"}</td>
                <td>{t.color_hex || "—"}</td>
                <td>
                  <.link navigate={~p"/admin/owner/teams/#{t.id}/edit"} class="btn btn-ghost btn-xs">
                    Edit
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@form == nil}>
          <button type="button" phx-click="new_team" class="btn btn-primary btn-sm">
            Add team
          </button>
        </div>
        <div :if={@form != nil} class="rounded-xl border border-base-300 bg-base-200 p-4 max-w-md">
          <.form
            for={@form}
            id="team-form"
            phx-change="validate_team"
            phx-submit="save_team"
            class="space-y-3"
          >
            <.input field={@form[:name]} type="text" label="Name" />
            <.input field={@form[:logo_path]} type="text" label="Logo path" />
            <.input field={@form[:color_hex]} type="text" label="Color (hex)" />
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create</button>
              <button type="button" phx-click="cancel_team" class="btn btn-ghost btn-sm">
                Cancel
              </button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
