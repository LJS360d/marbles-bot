defmodule Marbles.Analytics do
  @moduledoc """
  Analytics facade. Delegates to the configured adapter so dev can use SQL
  and prod can use a scalable backend (event stream, external service, etc.).
  """
  @default_adapter Marbles.Analytics.SQLAdapter

  defp adapter do
    Application.get_env(:marbles, :analytics_adapter, @default_adapter)
  end

  def record_pull(guild_id, user_id, meta \\ %{}) do
    adapter().record_pull(guild_id, user_id, meta)
  end

  def record_spawn(guild_id, channel_id, user_id, meta \\ %{}) do
    adapter().record_spawn(guild_id, channel_id, user_id, meta)
  end

  def pulls_today(guild_id \\ nil) do
    adapter().pulls_today(guild_id)
  end

  def spawns_today(guild_id \\ nil) do
    adapter().spawns_today(guild_id)
  end

  def guilds_count do
    adapter().guilds_count()
  end
end
