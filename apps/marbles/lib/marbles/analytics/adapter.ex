defmodule Marbles.Analytics.Adapter do
  @moduledoc """
  Behaviour for analytics backends. Dev can use SQL; prod can use a scalable
  store (e.g. event stream, external analytics service).
  """
  @callback record_pull(guild_id :: String.t() | nil, user_id :: binary(), meta :: map()) :: :ok | {:error, term()}
  @callback record_spawn(guild_id :: String.t() | nil, channel_id :: String.t() | nil, user_id :: binary() | nil, meta :: map()) :: :ok | {:error, term()}
  @callback pulls_today(guild_id :: String.t() | nil) :: non_neg_integer()
  @callback spawns_today(guild_id :: String.t() | nil) :: non_neg_integer()
  @callback guilds_count() :: non_neg_integer()
end
