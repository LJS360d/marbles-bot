defmodule Marbles.Analytics.AdminDashboard do
  @moduledoc false

  alias Marbles.{Accounts, Analytics, Catalog, Guilds, Repo}
  alias Marbles.Schema.{Marble, Pack}

  @type memory_map :: %{required(String.t()) => non_neg_integer()}
  @type memory_breakdown :: %{
          beam_total_mb: non_neg_integer(),
          process_mb: non_neg_integer(),
          atom_mb: non_neg_integer(),
          binary_mb: non_neg_integer(),
          code_mb: non_neg_integer(),
          ets_mb: non_neg_integer(),
          system_mb: non_neg_integer()
        }
  @type snapshot :: %{
          memory: memory_map(),
          memory_breakdown: memory_breakdown(),
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
    memory_raw = :erlang.memory()
    {_users, users_total} = Accounts.list_users(per_page: 1)
    pulls_today = Analytics.pulls_today()
    spawns_today = Analytics.spawns_today()

    %{
      memory: Enum.into(memory_raw, %{}, fn {k, v} -> {to_string(k), v} end),
      memory_breakdown: memory_breakdown(memory_raw),
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

  @spec memory_breakdown(keyword(non_neg_integer())) :: memory_breakdown()
  def memory_breakdown(memory_raw) when is_list(memory_raw) do
    total_mem = Keyword.get(memory_raw, :total, 0)

    %{
      beam_total_mb: div(total_mem, 1024 * 1024),
      process_mb: div(Keyword.get(memory_raw, :processes, 0), 1024 * 1024),
      atom_mb: div(Keyword.get(memory_raw, :atom, 0), 1024 * 1024),
      binary_mb: div(Keyword.get(memory_raw, :binary, 0), 1024 * 1024),
      code_mb: div(Keyword.get(memory_raw, :code, 0), 1024 * 1024),
      ets_mb: div(Keyword.get(memory_raw, :ets, 0), 1024 * 1024),
      system_mb: div(Keyword.get(memory_raw, :system, 0), 1024 * 1024)
    }
  end
end
