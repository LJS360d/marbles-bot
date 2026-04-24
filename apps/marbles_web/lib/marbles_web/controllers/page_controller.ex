defmodule MarblesWeb.PageController do
  use MarblesWeb, :controller

  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    render(conn, :home,
      discord_server_invite: Application.get_env(:marbles, :discord_server_invite),
      discord_bot_invite: Application.get_env(:marbles, :discord_bot_invite)
    )
  end

  @spec privacy_policy(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy, breadcrumbs: [{"Privacy Policy", nil}])
  end

  @spec terms_of_service(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def terms_of_service(conn, _params) do
    render(conn, :terms_of_service, breadcrumbs: [{"Terms of Service", nil}])
  end
end
