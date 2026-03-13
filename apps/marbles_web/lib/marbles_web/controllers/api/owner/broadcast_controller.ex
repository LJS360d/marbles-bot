defmodule MarblesWeb.Api.Owner.BroadcastController do
  use MarblesWeb, :controller
  alias Marbles.Broadcast

  def create(conn, %{"message" => message, "guild_ids" => guild_ids}) when is_list(guild_ids) do
    Broadcast.send_announcement(message, guild_ids)
    json(conn, %{ok: true})
  end

  def create(conn, %{"message" => message}) do
    Broadcast.send_announcement(message, :all)
    json(conn, %{ok: true})
  end

  def create(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{error: "message required"})
  end
end
