defmodule MarblesDiscordbot.Consumers.Interaction do
  use Nostrum.Consumer
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Interaction
  alias Nostrum.Api
  alias Marbles.{Catalog, Guilds, Analytics, Accounts, Collection, Gacha}
  alias MarblesDiscordbot.Embeds
  alias MarblesDiscordbot.Components
  require Logger

  def handle_event({:INTERACTION_CREATE, %Interaction{} = i, _ws_state})
      when is_nil(i.data.custom_id) do
    location =
      if i.guild_id do
        case Nostrum.Cache.GuildCache.get(i.guild_id) do
          {:ok, guild} -> "guild: '#{guild.name}'"
          _ -> "Unknown Guild"
        end
      else
        "DMs"
      end

    user = i.user || i.member.user
    Logger.info("From user '#{user.username}' in #{location}: /#{i.data.name}")

    response = handle_command(i.data.name, i)

    if response do
      case Api.create_interaction_response(i, response) do
        {:ok} ->
          :ok

        {:error, err} ->
          Logger.error("Interaction response failed: #{inspect(err)}")
      end
    end
  end

  defp get_option(i, name) do
    case i.data.options do
      nil ->
        nil

      opts ->
        opts
        |> Enum.find(fn o -> o.name == name or (is_map(o) and Map.get(o, :name) == name) end)
        |> then(fn o -> o && o.value end)
    end
  end

  def handle_command("spawnrate", %Interaction{} = i) do
    channel_id = i.channel_id && to_string(i.channel_id)
    guild_id = i.guild_id && to_string(i.guild_id)
    rate_opt = get_option(i, "rate")

    guild_name =
      if i.guild_id do
        case Nostrum.Cache.GuildCache.get(i.guild_id) do
          {:ok, g} -> g.name
          _ -> "Unknown"
        end
      else
        "DM"
      end

    if rate_opt == nil do
      current =
        if channel_id do
          case Guilds.get_channel(channel_id) do
            nil -> 0
            ch -> ch.spawn_rate
          end
        else
          0
        end

      content = "Current spawn rate in this channel: **#{current}%**"
      %{type: 4, data: %{content: content}}
    else
      rate = min(100, max(0, rate_opt * 1.0))

      channel_name =
        channel_id &&
          case Nostrum.Cache.GuildCache.get(i.guild_id) do
            {:ok, guild} ->
              guild.channels
              |> then(fn c -> (c && c.name) || "Unknown" end)

            _ ->
              "Unknown"
          end

      if channel_id && guild_id do
        case Guilds.upsert_channel_spawn_rate(
               channel_id,
               guild_id,
               guild_name,
               channel_name,
               rate
             ) do
          {:ok, ch} ->
            %{
              type: 4,
              data: %{content: "Spawn rate set to **#{ch.spawn_rate}%** in this channel."}
            }

          {:error, _} ->
            %{type: 4, data: %{content: "Failed to set spawn rate."}}
        end
      else
        %{type: 4, data: %{content: "This command can only be used in a server channel."}}
      end
    end
  end

  def handle_command("pull", i) do
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    pack_id_str = get_option(i, "pack")

    if pack_id_str == nil or pack_id_str == "" do
      # should never happen
      %{type: 4, data: %{content: "No pack selected."}}
    else
      case Ecto.UUID.cast(pack_id_str) do
        {:ok, pack_id} ->
          pack = Catalog.list_active_packs() |> Enum.find(fn p -> p.id == pack_id end)

          if pack == nil do
            %{type: 4, data: %{content: "That pack is not available."}}
          else
            free = Accounts.can_free_pull?(user_record)
            cost = pack.cost || 0

            if free or user_record.currency >= cost do
              guild_id_str = i.guild_id && to_string(i.guild_id)

              case Gacha.pull_from_pack(pack_id, user_record.id, guild_id_str) do
                {:ok, marble} ->
                  if not free do
                    Accounts.update_currency(user_record, -cost)
                  else
                    Accounts.set_last_free_pull_at(user_record)
                  end

                  spoiler_wrap = fn t -> "|| " <> t <> " ||" end

                  Collection.add_marble_to_collection(user_record.id, marble.id)

                  embed = Embeds.marble_embed(marble)

                  embed =
                    embed
                    |> Embed.put_description(spoiler_wrap.(embed.description || ""))
                    |> Embed.put_title(spoiler_wrap.(embed.title || ""))
                    |> Embed.put_footer("Has been added to your collection")

                  %{type: 4, data: %{embeds: [embed]}}

                {:error, _} ->
                  %{type: 4, data: %{content: "Could not pull from this pack. Try again later."}}
              end
            else
              %{
                type: 4,
                data: %{
                  content:
                    "You need **#{cost}** coins to pull from **#{pack.name}**. You have #{user_record.currency}."
                }
              }
            end
          end

        :error ->
          %{type: 4, data: %{content: "Invalid pack."}}
      end
    end
  end

  def handle_command("channels", i) do
    guild_id = i.guild_id && to_string(i.guild_id)

    if guild_id == nil do
      %{type: 4, data: %{content: "This command can only be used in a server."}}
    else
      case Nostrum.Api.Guild.channels(i.guild_id) do
        {:ok, channels} ->
          text_channels = Enum.filter(channels, fn c -> c.type == 0 or c.type == 5 end)

          channel_rates =
            Guilds.list_channels_by_guild(guild_id) |> Map.new(fn c -> {c.id, c.spawn_rate} end)

          lines =
            Enum.map(text_channels, fn c ->
              cid = to_string(c.id)
              rate = Map.get(channel_rates, cid, 0)
              icon = if rate > 0, do: ":green_circle:", else: ":red_circle:"
              "#{icon} <##{c.id}> **#{rate}%**"
            end)

          embed =
            %Embed{}
            |> Embed.put_title("Channels")
            |> Embed.put_description(
              Enum.join(lines, "\n")
              |> then(fn d -> if d == "", do: "No text channels.", else: d end)
            )

          %{type: 4, data: %{embeds: [embed]}}

        {:error, _} ->
          %{type: 4, data: %{content: "Could not list channels."}}
      end
    end
  end

  def handle_command("packs", _i) do
    packs = Catalog.list_active_packs(Date.utc_today(), :newest)

    if packs == [] do
      %{type: 4, data: %{content: "No packs are currently available."}}
    else
      page = 0
      pack = Enum.at(packs, page)
      embed = Embeds.pack_embed(pack, page + 1, length(packs))
      components = Components.packs_nav_components(packs, page)
      %{type: 4, data: %{embeds: [embed], components: components}}
    end
  end

  def handle_command("analytics", i) do
    guild_id = i.guild_id && to_string(i.guild_id)
    servers = Analytics.guilds_count()
    pulls_global = Analytics.pulls_today(nil)
    spawns_global = Analytics.spawns_today(nil)
    pulls_guild = if guild_id, do: Analytics.pulls_today(guild_id), else: 0
    spawns_guild = if guild_id, do: Analytics.spawns_today(guild_id), else: 0

    fields = [
      %{name: "Servers", value: to_string(servers), inline: true},
      %{name: "Pulls today (global)", value: to_string(pulls_global), inline: true},
      %{name: "Spawns today (global)", value: to_string(spawns_global), inline: true}
    ]

    fields =
      if guild_id do
        fields ++
          [
            %{name: "Pulls today (this server)", value: to_string(pulls_guild), inline: true},
            %{name: "Spawns today (this server)", value: to_string(spawns_guild), inline: true}
          ]
      else
        fields
      end

    embed = %Embed{
      title: "Analytics",
      description: "Bot statistics",
      fields: fields
    }

    %{type: 4, data: %{embeds: [embed]}}
  end

  def handle_command("collection", i) do
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {items, total} =
      Collection.list_user_inventory(user_record.id, page: 1, sort: :rarity_level_name)

    if total == 0 do
      %{type: 4, data: %{content: "Your collection is empty. Pull marbles or catch spawns!"}}
    else
      embed = Embeds.collection_embed(items, 1, total, :rarity_level_name, user)
      components = Components.collection_components(1, total, :rarity_level_name)
      %{type: 4, data: %{embeds: [embed], components: components}}
    end
  end

  def handle_command("trade", _i) do
    %{type: 4, data: %{content: "Trade is not implemented yet."}}
  end

  def handle_command(_, _), do: nil
end
