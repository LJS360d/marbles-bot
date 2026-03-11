defmodule MarblesWeb.Live.AuthHooks do
  import Phoenix.Component
  alias Marbles.Accounts

  def on_mount(:assign_current_user, _params, session, socket) do
    user =
      case session["user_id"] do
        nil -> nil
        id -> Accounts.get_user!(id)
      end

    {:cont, assign(socket, :current_user, user)}
  end
end
