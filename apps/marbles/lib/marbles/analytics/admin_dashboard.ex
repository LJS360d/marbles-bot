defmodule Marbles.Analytics.AdminDashboard do
  @moduledoc false

  alias Marbles.{Accounts, Analytics, Catalog, Guilds, Repo}
  alias Marbles.Schema.{Marble, Pack}

  @type snapshot :: %{
          guilds_count: non_neg_integer(),
          users_count: non_neg_integer(),
          marbles_count: non_neg_integer(),
          packs_count: non_neg_integer(),
          teams_count: non_neg_integer(),
          pulls_today: non_neg_integer(),
          spawns_today: non_neg_integer(),
          max_events: pos_integer(),
          guilds: [map()]
        }

  @spec snapshot() :: snapshot()
  def snapshot do
    {_users, users_total} = Accounts.list_users(per_page: 1)
    pulls_today = Analytics.pulls_today()
    spawns_today = Analytics.spawns_today()

    %{
      guilds_count: Analytics.guilds_count(),
      users_count: users_total,
      marbles_count: Repo.aggregate(Marble, :count, :id),
      packs_count: Repo.aggregate(Pack, :count, :id),
      teams_count: length(Catalog.list_teams()),
      pulls_today: pulls_today,
      spawns_today: spawns_today,
      max_events: max(pulls_today + spawns_today, 1),
      guilds:
        Enum.map(Guilds.list_guilds_with_channel_count(), fn {guild, channel_count} ->
          %{id: guild.id, name: guild.name, channel_count: channel_count}
        end)
    }
  end
end
