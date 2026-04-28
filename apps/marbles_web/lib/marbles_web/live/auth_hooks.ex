defmodule MarblesWeb.Live.AuthHooks do
  import Phoenix.Component
  import Phoenix.LiveView
  use MarblesWeb, :verified_routes

  @spec on_mount(:assign_current_user, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:assign_current_user, _params, session, socket) do
    user = MarblesWeb.Authz.fetch_current_user(session["user_id"])

    {:cont, assign(socket, :current_user, user)}
  end

  @spec on_mount(:require_owner, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_owner, _params, session, socket) do
    user = MarblesWeb.Authz.fetch_current_user(session["user_id"])

    if MarblesWeb.Authz.authorize(user, :owner) == :ok do
      {:cont, assign(socket, :current_user, user)}
    else
      {:halt,
       socket
       |> put_flash(:error, "Not authorized.")
       |> redirect(to: ~p"/")}
    end
  end
end
