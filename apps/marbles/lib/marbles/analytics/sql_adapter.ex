defmodule Marbles.Analytics.SQLAdapter do
  @behaviour Marbles.Analytics.Adapter
  alias Marbles.Repo
  alias Marbles.Schema.{AnalyticsEvent, Guild}
  import Ecto.Query

  @impl true
  def record_pull(guild_id, user_id, meta \\ %{}) do
    record_event("pull", guild_id, nil, user_id, meta)
  end

  @impl true
  def record_spawn(guild_id, channel_id, user_id, meta \\ %{}) do
    record_event("spawn", guild_id, channel_id, user_id, meta)
  end

  @impl true
  def record_event(event_type, guild_id, channel_id, user_id, meta \\ %{}) do
    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(%{
      event_type: event_type,
      guild_id: guild_id,
      channel_id: channel_id,
      user_id: user_id,
      meta: meta
    })
    |> Repo.insert()
    |> case do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(
          Marbles.PubSub,
          "admin_dashboard",
          {:admin_dashboard, :stats_updated}
        )

        :ok

      e ->
        e
    end
  end

  @impl true
  def pulls_today(guild_id \\ nil) do
    today_start = NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00])
    q = from(e in AnalyticsEvent, where: e.event_type == "pull" and e.inserted_at >= ^today_start)
    q = if guild_id, do: from(e in q, where: e.guild_id == ^guild_id), else: q
    Repo.aggregate(q, :count, :id)
  end

  @impl true
  def spawns_today(guild_id \\ nil) do
    today_start = NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00])

    q =
      from(e in AnalyticsEvent, where: e.event_type == "spawn" and e.inserted_at >= ^today_start)

    q = if guild_id, do: from(e in q, where: e.guild_id == ^guild_id), else: q
    Repo.aggregate(q, :count, :id)
  end

  @impl true
  def guilds_count do
    Repo.aggregate(Guild, :count, :id)
  end
end
