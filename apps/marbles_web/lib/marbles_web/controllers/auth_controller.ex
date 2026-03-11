defmodule MarblesWeb.AuthController do
  use MarblesWeb, :controller
  plug Ueberauth

  alias Marbles.Accounts

  def login_page(conn, _params) do
    render(conn, :login_page)
  end

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_failure: _}} = conn, _params) do
    conn
    |> put_flash(:error, "Login failed.")
    |> redirect(to: ~p"/login")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    attrs = %{
      username: auth.info.nickname || auth.info.name,
      display_name: auth.info.name,
      platform: "discord",
      platform_id: auth.uid
    }

    case Accounts.ensure_user(attrs) do
      {:ok, user} ->
        user = maybe_promote_owner(user)
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Logged in.")
        |> redirect(to: ~p"/")
      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create or find your account.")
        |> redirect(to: ~p"/login")
    end
  end

  defp maybe_promote_owner(user) do
    owner_ids = Application.get_env(:marbles_web, :owner_platform_ids, [])
    if user.platform_id in owner_ids do
      case Accounts.set_role(user, :owner) do
        {:ok, updated} -> updated
        {:error, _} -> user
      end
    else
      user
    end
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end
end
