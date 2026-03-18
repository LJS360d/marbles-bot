defmodule MarblesWeb.Live.AuthHooks do
  import Phoenix.Component
  import Phoenix.LiveView
  use MarblesWeb, :verified_routes
  alias Marbles.Accounts

  def on_mount(:assign_current_user, _params, session, socket) do
    user =
      case session["user_id"] do
        nil -> nil
        id -> Accounts.get_user(id)
      end

    {:cont, assign(socket, :current_user, user)}
  end

  def on_mount(:require_owner, _params, session, socket) do
    user =
      case session["user_id"] do
        nil -> nil
        id -> Accounts.get_user(id)
      end

    if user && user.role == :owner do
      {:cont, assign(socket, :current_user, user)}
    else
      {:halt,
       socket
       |> put_flash(:error, "Not authorized.")
       |> redirect(to: ~p"/")}
    end
  end
end
