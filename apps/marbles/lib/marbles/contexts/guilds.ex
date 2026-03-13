defmodule Marbles.Guilds do
  alias Marbles.Repo
  alias Marbles.Schema.{Guild, Channel}
  import Ecto.Query

  def get_or_create_guild(guild_id, name, platform \\ "discord", image_url \\ nil) do
    case Repo.get(Guild, guild_id) do
      nil ->
        attrs = %{id: guild_id, name: name, platform: platform}
        attrs = if image_url, do: Map.put(attrs, :image_url, image_url), else: attrs
        %Guild{}
        |> Guild.changeset(attrs)
        |> Repo.insert()

      guild ->
        if image_url && guild.image_url != image_url do
          guild
          |> Guild.changeset(%{image_url: image_url})
          |> Repo.update()
        else
          {:ok, guild}
        end
    end
  end

  def get_channel(channel_id) do
    # TODO try to hit a memcache first, the access is very frequent
    Repo.get(Channel, channel_id)
  end

  def upsert_channel_spawn_rate(channel_id, guild_id, guild_name, channel_name, spawn_rate, opts \\ []) do
    image_url = Keyword.get(opts, :image_url)
    _ = get_or_create_guild(guild_id, guild_name, "discord", image_url)

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

  def list_guilds_with_channel_count do
    from(g in Guild,
      left_join: c in Channel,
      on: c.guild_id == g.id,
      group_by: g.id,
      select: {g, count(c.id)}
    )
    |> Repo.all()
  end

  @doc """
  Paginated guild insights: list of {guild, channel_count} with sort.
  sort: "name", "name_desc", "channels", "channels_desc"
  Returns {list, total_count}.
  """
  def list_guilds_insights(sort \\ "channels_desc", page \\ 1, per_page \\ 10) do
    total = Repo.aggregate(Guild, :count, :id)
    offset = (page - 1) * per_page

    query =
      case sort do
        "name" ->
          from(g in Guild,
            left_join: c in Channel,
            on: c.guild_id == g.id,
            group_by: g.id,
            order_by: [asc: g.name],
            select: {g, count(c.id)},
            limit: ^per_page,
            offset: ^offset
          )

        "name_desc" ->
          from(g in Guild,
            left_join: c in Channel,
            on: c.guild_id == g.id,
            group_by: g.id,
            order_by: [desc: g.name],
            select: {g, count(c.id)},
            limit: ^per_page,
            offset: ^offset
          )

        "channels" ->
          from(g in Guild,
            left_join: c in Channel,
            on: c.guild_id == g.id,
            group_by: g.id,
            order_by: [asc: count(c.id)],
            select: {g, count(c.id)},
            limit: ^per_page,
            offset: ^offset
          )

        _ ->
          from(g in Guild,
            left_join: c in Channel,
            on: c.guild_id == g.id,
            group_by: g.id,
            order_by: [desc: count(c.id)],
            select: {g, count(c.id)},
            limit: ^per_page,
            offset: ^offset
          )
      end

    {Repo.all(query), total}
  end
end
