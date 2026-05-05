defmodule Marbles.Analytics do
  @moduledoc """
  Analytics facade. Delegates to the configured adapter so dev can use SQL
  and prod can use a scalable backend (event stream, external service, etc.).
  """
  @default_adapter Marbles.Analytics.SQLAdapter

  defp adapter do
    Application.get_env(:marbles, :analytics_adapter, @default_adapter)
  end

  @spec record_pull(String.t() | nil, Ecto.UUID.t(), map()) :: :ok | {:error, term()}
  def record_pull(guild_id, user_id, meta \\ %{}) do
    adapter().record_pull(guild_id, user_id, meta)
  end

  @spec record_spawn(String.t() | nil, String.t() | nil, Ecto.UUID.t() | nil, map()) ::
          :ok | {:error, term()}
  def record_spawn(guild_id, channel_id, user_id, meta \\ %{}) do
    adapter().record_spawn(guild_id, channel_id, user_id, meta)
  end

  @spec record_event(String.t(), String.t() | nil, String.t() | nil, Ecto.UUID.t() | nil, map()) ::
          :ok | {:error, term()}
  def record_event(event_type, guild_id \\ nil, channel_id \\ nil, user_id \\ nil, meta \\ %{}) do
    adapter().record_event(event_type, guild_id, channel_id, user_id, meta)
  end

  @spec pulls_today(String.t() | nil) :: non_neg_integer()
  def pulls_today(guild_id \\ nil) do
    adapter().pulls_today(guild_id)
  end

  @spec spawns_today(String.t() | nil) :: non_neg_integer()
  def spawns_today(guild_id \\ nil) do
    adapter().spawns_today(guild_id)
  end

  @spec guilds_count() :: non_neg_integer()
  def guilds_count do
    adapter().guilds_count()
  end
end
