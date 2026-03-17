defmodule MarblesWeb.Admin.OwnerTeamEditLive do
  use MarblesWeb, :live_view
  alias Marbles.Catalog
  alias Marbles.Schema.Team

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Edit team")
     |> assign(:current_scope, :owner_admin)
     |> assign(:wide, true)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Teams", ~p"/admin/owner/teams"},
       {"Edit", nil}
     ])}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    team = Catalog.get_team!(id)
    form = team |> Team.changeset(%{}) |> to_form(as: "team")

    {:noreply,
     socket
     |> assign(:team, team)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"team" => params}, socket) do
    changeset =
      socket.assigns.team
      |> Team.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "team"))}
  end

  @impl true
  def handle_event("save", %{"team" => params}, socket) do
    case Catalog.update_team(socket.assigns.team, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Team updated.")
         |> push_navigate(to: ~p"/admin/owner/teams")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "team"))}
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
        <h1 class="text-2xl font-semibold">Edit {@team.name}</h1>

        <.form
          for={@form}
          id="team-edit-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:logo_path]} type="text" label="Logo path" />
          <.input field={@form[:color_hex]} type="text" label="Color (hex)" />
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <.link navigate={~p"/admin/owner/teams"} class="btn btn-ghost">Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
