defmodule Marbles.Analytics.SQLAdapter do
  @behaviour Marbles.Analytics.Adapter
  alias Marbles.Repo
  alias Marbles.Schema.{AnalyticsEvent, Guild}
  import Ecto.Query

  @impl true
  def record_pull(guild_id, user_id, meta \\ %{}) do
    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(%{
      event_type: "pull",
      guild_id: guild_id,
      user_id: user_id,
      meta: meta
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      e -> e
    end
  end

  @impl true
  def record_spawn(guild_id, channel_id, user_id, meta \\ %{}) do
    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(%{
      event_type: "spawn",
      guild_id: guild_id,
      channel_id: channel_id,
      user_id: user_id,
      meta: meta
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      e -> e
    end
  end

  @impl true
  def pulls_today(guild_id \\ nil) do
    today = Date.utc_today()
    q = from(e in AnalyticsEvent, where: e.event_type == "pull" and e.inserted_at >= ^today)
    q = if guild_id, do: from(e in q, where: e.guild_id == ^guild_id), else: q
    Repo.aggregate(q, :count, :id)
  end

  @impl true
  def spawns_today(guild_id \\ nil) do
    today =
      Date.utc_today()

    q = from(e in AnalyticsEvent, where: e.event_type == "spawn" and e.inserted_at >= ^today)
    q = if guild_id, do: from(e in q, where: e.guild_id == ^guild_id), else: q
    Repo.aggregate(q, :count, :id)
  end

  @impl true
  def guilds_count do
    Repo.aggregate(Guild, :count, :id)
  end
end
