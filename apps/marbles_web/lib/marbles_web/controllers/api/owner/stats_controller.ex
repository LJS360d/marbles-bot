defmodule MarblesWeb.Api.Owner.StatsController do
  use MarblesWeb, :controller
  alias Marbles.Analytics
  alias Marbles.Guilds
  alias Marbles.Accounts
  alias Marbles.Repo
  alias Marbles.Schema.{Marble, Pack}

  def index(conn, _params) do
    memory = :erlang.memory() |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
    guilds_count = Analytics.guilds_count()
    guilds_with_channels = Guilds.list_guilds_with_channel_count()
    {_users, users_total} = Accounts.list_users(per_page: 1)
    users_count = users_total
    marbles_count = Repo.aggregate(Marble, :count, :id)
    packs_count = Repo.aggregate(Pack, :count, :id)
    pulls_today = Analytics.pulls_today()
    spawns_today = Analytics.spawns_today()

    json(conn, %{
      memory: memory,
      guilds_count: guilds_count,
      users_count: users_count,
      marbles_count: marbles_count,
      packs_count: packs_count,
      pulls_today: pulls_today,
      spawns_today: spawns_today,
      guilds:
        Enum.map(guilds_with_channels, fn {g, ch_count} ->
          %{id: g.id, name: g.name, channel_count: ch_count}
        end)
    })
  end
end
