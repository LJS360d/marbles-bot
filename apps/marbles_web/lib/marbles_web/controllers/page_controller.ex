defmodule MarblesWeb.PageController do
  use MarblesWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      discord_server_invite: Application.get_env(:marbles, :discord_server_invite),
      discord_bot_invite: Application.get_env(:marbles, :discord_bot_invite)
    )
  end
end
