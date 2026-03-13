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

  def handle_command("spawnrate", %Interaction{data: %{options: options}} = i) do
    # Find the subcommand in the list
    case Enum.find(options || [], fn opt -> opt.name in ["list", "set"] end) do
      %{name: "list"} ->
        handle_channels_list(i)

      %{name: "set", options: sub_opts} ->
        # sub_opts might be nil if the user didn't provide any arguments,
        # so we use || [] to prevent crashes in our helpers
        process_spawnrate_set(i, sub_opts || [])

      _ ->
        %{type: 4, data: %{content: "Unknown subcommand."}, ephemeral: true}
    end
  end

  def handle_command("pull", %Interaction{} = i) do
    username =
      case Nostrum.Cache.UserCache.get(i.user.id) do
        {:ok, %{username: ""}} -> "Invalid Username"
        {:ok, %{username: username}} -> username
        _ -> "Unknown Username"
      end

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(i.user.id),
        platform: "discord",
        username: username
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

  def handle_channels_list(%Interaction{guild_id: guild_id} = _i) do
    if is_nil(guild_id) do
      %{
        type: 4,
        data: %{content: "This command can only be used in text channel.", ephemeral: true}
      }
    else
      case Api.Guild.channels(guild_id) do
        {:ok, channels} ->
          # Pre-fetch rates into a map for O(1) lookup during enumeration
          channel_rates =
            guild_id
            |> to_string()
            |> Guilds.list_channels_by_guild()
            |> Map.new(&{to_string(&1.id), &1.spawn_rate})

          description =
            channels
            |> Enum.filter(&(&1.type in [0, 5]))
            |> Enum.map_join("\n", fn c ->
              rate = Map.get(channel_rates, to_string(c.id), 0)
              icon = if rate > 0, do: ":green_circle:", else: ":red_circle:"
              "#{icon} <##{c.id}> **#{rate}%**"
            end)
            |> then(&if &1 == "", do: "No text channels.", else: &1)

          embed = %Embed{} |> Embed.put_title("Channels") |> Embed.put_description(description)
          %{type: 4, data: %{embeds: [embed]}}

        {:error, _} ->
          %{type: 4, data: %{content: "Could not list channels."}}
      end
    end
  end

  def process_spawnrate_set(%Interaction{} = i, opts) do
    channel_id = (get_option(opts, "channel") || i.channel_id) |> to_string()
    rate_opt = get_option(opts, "rate")

    cond do
      is_nil(i.guild_id) ->
        %{
          type: 4,
          data: %{content: "This command can only be used in a text channel.", ephemeral: true}
        }

      is_nil(rate_opt) ->
        current = (Guilds.get_channel(channel_id) || %{spawn_rate: 0}).spawn_rate
        %{type: 4, data: %{content: "Current spawn rate in <##{channel_id}>: **#{current}%**"}}

      true ->
        # Calculate derived data for the upsert
        rate = (rate_opt * 1.0) |> max(0.0) |> min(100.0)

        {guild_name, icon_url} =
          case Nostrum.Cache.GuildCache.get(i.guild_id) do
            {:ok, g} -> {g.name, Nostrum.Struct.Guild.icon_url(g)}
            _ -> {"Unknown", nil}
          end

        channel_name =
          with {:ok, guild} <- Nostrum.Cache.GuildCache.get(i.guild_id),
               id_int <- String.to_integer(channel_id),
               %{name: name} <- Map.get(guild.channels || %{}, id_int) do
            name
          else
            _ -> "Unknown"
          end

        case Guilds.upsert_channel_spawn_rate(
               channel_id,
               to_string(i.guild_id),
               guild_name,
               channel_name,
               rate,
               image_url: icon_url
             ) do
          {:ok, ch} ->
            %{
              type: 4,
              data: %{content: "Spawn rate set to **#{ch.spawn_rate}%** in <##{channel_id}>."}
            }

          {:error, _} ->
            %{type: 4, data: %{content: "Failed to set spawn rate."}}
        end
    end
  end
end
