defmodule MarblesWeb.Plugs.Auth do
  import Plug.Conn
  import Phoenix.Controller
  use MarblesWeb, :verified_routes
  alias Marbles.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = if user_id, do: Accounts.get_user!(user_id), else: nil
    assign(conn, :current_user, user)
  end

  def require_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  def require_owner(conn, _opts) do
    user = conn.assigns[:current_user]

    if owner?(user) do
      conn
    else
      conn
      |> put_flash(:error, "Not authorized.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def require_server_admin_or_owner(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && (user.role == :server_admin || owner?(user)) do
      conn
    else
      conn
      |> put_flash(:error, "Not authorized.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp owner?(nil), do: false
  defp owner?(user), do: user.role == :owner
end
