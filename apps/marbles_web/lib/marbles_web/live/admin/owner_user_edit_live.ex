defmodule MarblesWeb.Admin.OwnerUserEditLive do
  use MarblesWeb, :live_view
  alias Marbles.Accounts
  alias Marbles.Schema.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Edit user")
     |> assign(:current_scope, :owner_admin)
     |> assign(:wide, true)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Users", ~p"/admin/owner/users"},
       {"Edit", nil}
     ])}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    user = Accounts.get_user!(id)
    form = user |> User.changeset(%{}) |> to_form(as: "user")

    {:noreply,
     socket
     |> assign(:user, user)
     |> assign(:form, form)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Users", ~p"/admin/owner/users"},
       {Accounts.primary_display_name(user), ~p"/admin/owner/users/#{user.id}"},
       {"Edit", nil}
     ])}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> User.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_user(socket.assigns.user, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated.")
         |> push_navigate(to: ~p"/admin/owner/users/#{socket.assigns.user.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
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
        <h1 class="text-2xl font-semibold">Edit {Accounts.primary_display_name(@user)}</h1>

        <.form
          for={@form}
          id="user-edit-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:display_name]} type="text" label="Display name" />
          <.input field={@form[:currency]} type="number" label="Currency" />
          <.input
            field={@form[:role]}
            type="select"
            label="Role"
            options={[{"Regular", "regular"}, {"Server admin", "server_admin"}, {"Owner", "owner"}]}
          />
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <.link navigate={~p"/admin/owner/users/#{@user.id}"} class="btn btn-ghost">Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
