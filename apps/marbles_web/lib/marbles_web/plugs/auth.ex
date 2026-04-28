defmodule MarblesWeb.Plugs.Auth do
  import Plug.Conn
  import Phoenix.Controller
  use MarblesWeb, :verified_routes

  @spec init(term()) :: term()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, opts) do
    user = conn |> get_session(:user_id) |> MarblesWeb.Authz.fetch_current_user()
    conn = assign(conn, :current_user, user)

    case opts do
      :require_user -> require_user(conn, opts)
      :require_owner -> require_owner(conn, opts)
      :require_server_admin_or_owner -> require_server_admin_or_owner(conn, opts)
      _ -> conn
    end
  end

  @spec require_user(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def require_user(conn, _opts) do
    if MarblesWeb.Authz.authorize(conn.assigns[:current_user], :user) == :ok do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @spec require_owner(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def require_owner(conn, _opts) do
    if MarblesWeb.Authz.authorize(conn.assigns[:current_user], :owner) == :ok do
      conn
    else
      conn
      |> put_flash(:error, "Not authorized.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  @spec require_server_admin_or_owner(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def require_server_admin_or_owner(conn, _opts) do
    if MarblesWeb.Authz.authorize(conn.assigns[:current_user], :server_admin_or_owner) == :ok do
      conn
    else
      conn
      |> put_flash(:error, "Not authorized.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end
