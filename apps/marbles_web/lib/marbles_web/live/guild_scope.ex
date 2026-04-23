defmodule MarblesWeb.Live.GuildScope do
  @moduledoc """
  Assigns `guild_route_scope` (`:server` or `:owner`) for shared guild list/detail LiveViews.
  Use `:server_guilds` on `/admin` routes and `:owner_guilds` on `/admin/owner/guilds` routes.
  """
  import Phoenix.Component

  @spec on_mount(:server_guilds | :owner_guilds, map(), map(), map()) :: {:cont, map()}
  def on_mount(:server_guilds, _params, _session, socket) do
    {:cont, assign(socket, :guild_route_scope, :server)}
  end

  def on_mount(:owner_guilds, _params, _session, socket) do
    {:cont, assign(socket, :guild_route_scope, :owner)}
  end
end
