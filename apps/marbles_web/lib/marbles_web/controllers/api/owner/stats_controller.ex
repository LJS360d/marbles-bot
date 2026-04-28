defmodule MarblesWeb.Api.Owner.StatsController do
  use MarblesWeb, :controller

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    snapshot = Marbles.Analytics.AdminDashboard.snapshot()

    json(conn, %{
      memory: snapshot.memory,
      guilds_count: snapshot.guilds_count,
      users_count: snapshot.users_count,
      marbles_count: snapshot.marbles_count,
      packs_count: snapshot.packs_count,
      pulls_today: snapshot.pulls_today,
      spawns_today: snapshot.spawns_today,
      guilds: snapshot.guilds
    })
  end
end
