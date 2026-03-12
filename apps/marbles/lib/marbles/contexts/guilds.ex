defmodule Marbles.Guilds do
  alias Marbles.Repo
  alias Marbles.Schema.{Guild, Channel}
  import Ecto.Query

  def get_or_create_guild(guild_id, name) do
    case Repo.get(Guild, guild_id) do
      nil ->
        %Guild{}
        |> Guild.changeset(%{id: guild_id, name: name})
        |> Repo.insert()

      guild ->
        {:ok, guild}
    end
  end

  def get_channel(channel_id) do
    # TODO try to hit a memcache first, the access is very frequent
    Repo.get(Channel, channel_id)
  end

  def upsert_channel_spawn_rate(channel_id, guild_id, guild_name, channel_name, spawn_rate) do
    _ = get_or_create_guild(guild_id, guild_name)

    case Repo.get(Channel, channel_id) do
      nil ->
        %Channel{}
        |> Channel.changeset(%{
          id: channel_id,
          guild_id: guild_id,
          name: channel_name,
          spawn_rate: spawn_rate
        })
        |> Repo.insert()

      channel ->
        channel
        |> Channel.changeset(%{name: channel_name, spawn_rate: spawn_rate})
        |> Repo.update()
    end
  end

  def list_channels_by_guild(guild_id) do
    from(c in Channel, where: c.guild_id == ^guild_id)
    |> Repo.all()
  end
end
