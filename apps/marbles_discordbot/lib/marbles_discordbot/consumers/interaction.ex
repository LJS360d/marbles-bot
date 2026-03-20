defmodule MarblesDiscordbot.Consumers.Interaction do
  use Nostrum.Consumer
  alias Nostrum.Struct.Embed.Field
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Interaction
  alias Nostrum.Api
  alias Marbles.{Catalog, Guilds, Analytics, Accounts, Collection, Daily}
  alias MarblesDiscordbot.{Embeds, Components, PullSession}
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

  defp get_option(options, name) do
    case options do
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

    pack_id_str = get_option(i.data.options, "pack")

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
            owner_id = i.user.id

            %{
              type: 4,
              data: %{
                content: Embeds.pull_session_message_content(user_record, pack),
                embeds: [Embeds.pull_banner_embed(pack)],
                components: PullSession.action_row(user_record, pack, owner_id)
              }
            }
          end

        :error ->
          %{type: 4, data: %{content: "Invalid pack."}}
      end
    end
  end

  def handle_command("packs", %Interaction{} = i) do
    packs = Catalog.list_active_packs(Date.utc_today(), :newest)
    uid = (i.user || i.member.user).id

    if packs == [] do
      %{type: 4, data: %{content: "No packs are currently available."}}
    else
      page = 0
      pack = Enum.at(packs, page)
      embed = Embeds.pack_embed(pack, page + 1, length(packs))
      components = MarblesDiscordbot.Components.packs_nav_components(packs, page, uid)
      %{type: 4, data: %{embeds: [embed], components: components}}
    end
  end

  def handle_command("analytics", i) do
    guild_id = i.guild_id && to_string(i.guild_id)
    pulls_global = Analytics.pulls_today(nil)
    spawns_global = Analytics.spawns_today(nil)
    pulls_guild = if guild_id, do: Analytics.pulls_today(guild_id), else: 0
    spawns_guild = if guild_id, do: Analytics.spawns_today(guild_id), else: 0
    bot_version = Application.spec(:marbles_discordbot, :vsn)
    core_version = Application.spec(:marbles, :vsn)

    fields = [
      %Field{name: "Pulls today (global)", value: to_string(pulls_global), inline: true},
      %Field{name: "Spawns today (global)", value: to_string(spawns_global), inline: true},
      %Field{name: "\t", value: "\t"}
    ]

    fields =
      if guild_id do
        fields ++
          [
            %Field{
              name: "Pulls today (this server)",
              value: to_string(pulls_guild),
              inline: true
            },
            %Field{
              name: "Spawns today (this server)",
              value: to_string(spawns_guild),
              inline: true
            }
          ]
      else
        fields
      end

    embed =
      %Embed{
        fields: fields
      }
      |> Embed.put_title("Analytics")
      |> Embed.put_description("Bot statistics")
      |> Embed.put_footer("bot v#{bot_version} | core v#{core_version}")

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

  def handle_command("daily", i) do
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    case Daily.claim_daily(user_record.id) do
      {:ok, %{coins: coins, streak: streak, items: items}} ->
        items_text =
          if Enum.empty?(items) do
            ""
          else
            "You also received: " <> Enum.map_join(items, ", ", & &1.name)
          end

        content =
          "You claimed your daily reward! You received **#{coins}** coins. Your current streak is **#{streak}**. #{items_text}"

        %{type: 4, data: %{content: content}}

      {:error, reason} ->
        %{type: 4, data: %{content: "Could not claim daily reward: #{reason}"}}
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
