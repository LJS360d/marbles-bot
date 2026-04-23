defmodule MarblesDiscordbot.Consumers.Interaction do
  use Nostrum.Consumer
  alias Nostrum.Struct.Embed.Field
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Interaction
  alias Nostrum.Api
  alias Marbles.{Catalog, Guilds, Analytics, Accounts, Collection, Daily, Leaderboards}
  alias Marbles.Economy.{Currency, MineRoster, Upgrades, Shop, Effects}
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

    response =
      if i.type == 4 do
        handle_autocomplete(i.data.name, i)
      else
        handle_command(i.data.name, i)
      end

    if response do
      case Api.create_interaction_response(i, response) do
        {:ok} ->
          :ok

        {:error, err} ->
          Logger.error("Interaction response failed: #{inspect(err)}")
      end
    end
  end

  defp first_subcommand(%{data: %{options: opts}}) when is_list(opts) do
    case List.first(opts) do
      %{name: n, options: o} -> {n, o || []}
      %{name: n} -> {n, []}
      _ -> {nil, []}
    end
  end

  defp first_subcommand(_), do: {nil, []}

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

  defp focused_option(options) when is_list(options) do
    Enum.find_value(options, fn opt ->
      cond do
        Map.get(opt, :focused) == true -> opt
        is_list(Map.get(opt, :options)) -> focused_option(opt.options)
        true -> nil
      end
    end)
  end

  defp focused_option(_), do: nil

  defp resolve_target(i, option_name) do
    invoker = i.user || i.member.user
    target_id = get_option(i.data.options, option_name)
    explicit_target? = not is_nil(target_id)

    sid =
      case target_id do
        nil -> to_string(invoker.id)
        id when is_integer(id) -> to_string(id)
        id when is_binary(id) -> id
        _ -> to_string(invoker.id)
      end

    invoker_sid = to_string(invoker.id)
    self_target? = sid == invoker_sid

    target_discord =
      cond do
        self_target? ->
          invoker

        true ->
          case Integer.parse(sid) do
            {uid, ""} ->
              case Nostrum.Cache.UserCache.get(uid) do
                {:ok, u} ->
                  u

                _ ->
                  case Nostrum.Api.User.get(uid) do
                    {:ok, u} -> u
                    _ -> nil
                  end
              end

            _ ->
              nil
          end
      end

    target_user = Accounts.get_user_by_platform(sid, "discord")
    target_identity = Accounts.get_identity_by_platform(sid, "discord")

    %{
      discord_id: sid,
      discord_user: target_discord,
      internal_user: target_user,
      identity_username: target_identity && target_identity.username,
      invoker_discord_user: invoker,
      explicit_target?: explicit_target?
    }
  end

  defp user_name(%{discord_user: %{username: u}}) when is_binary(u), do: u

  defp user_name(%{internal_user: u}) when not is_nil(u) do
    case u.display_name do
      n when is_binary(n) and n != "" -> n
      _ -> "User"
    end
  end

  defp user_name(%{identity_username: u}) when is_binary(u) and u != "", do: u
  defp user_name(_), do: "User"

  defp display_name(tgt = %{discord_user: du}, internal_user) do
    identity_name =
      if internal_user do
        Accounts.identity_username(internal_user, "discord")
      else
        nil
      end

    cond do
      not is_nil(internal_user) and is_binary(internal_user.display_name) and
          String.trim(internal_user.display_name) != "" ->
        internal_user.display_name

      is_binary(identity_name) and String.trim(identity_name) != "" ->
        identity_name

      not is_nil(du) and is_binary(du.global_name) and du.global_name != "" ->
        du.global_name

      not is_nil(du) and is_binary(du.username) and du.username != "" ->
        du.username

      is_binary(Map.get(tgt, :identity_username)) and Map.get(tgt, :identity_username) != "" ->
        Map.get(tgt, :identity_username)

      true ->
        user_name(tgt)
    end
  end

  defp maybe_put_thumbnail(embed, nil), do: embed
  defp maybe_put_thumbnail(embed, ""), do: embed
  defp maybe_put_thumbnail(embed, url), do: Embed.put_thumbnail(embed, url)

  defp format_duration(sec) when is_integer(sec) and sec > 0 do
    if rem(sec, 3600) == 0 do
      "#{div(sec, 3600)}h"
    else
      "#{div(sec, 60)}m"
    end
  end

  defp format_duration(_), do: "0m"

  defp handle_autocomplete("mines", i) do
    user = i.user || i.member.user

    {:ok, ur} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {sub, _opts} = first_subcommand(i)
    focused = focused_option(i.data.options || [])
    query = if focused, do: to_string(focused.value || ""), else: ""

    names =
      case sub do
        "add" -> MineRoster.autocomplete_owned(ur.id, query)
        "remove" -> MineRoster.autocomplete_roster(ur.id, query)
        _ -> []
      end

    choices = Enum.map(names, fn n -> %{name: String.slice(n, 0, 100), value: n} end)
    %{type: 8, data: %{choices: choices}}
  end

  defp handle_autocomplete(_, _), do: nil

  defp price_line(%{coin: c, dust: d}) do
    cond do
      c > 0 and d > 0 ->
        "**#{c}** #{Currency.coin_emoji()} + **#{d}** #{Currency.dust_emoji()}"

      c > 0 ->
        "**#{c}** #{Currency.coin_emoji()}"

      true ->
        "**#{d}** #{Currency.dust_emoji()}"
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
      |> Embed.put_footer("bot v#{bot_version} | core v#{core_version}")

    %{type: 4, data: %{embeds: [embed]}}
  end

  def handle_command("collection", i) do
    tgt = resolve_target(i, "user")

    cond do
      is_nil(tgt.internal_user) and get_option(i.data.options, "user") != nil ->
        %{type: 4, data: %{content: "That user has no profile in this system yet."}}

      true ->
        user = i.user || i.member.user

        user_record =
          if tgt.internal_user do
            tgt.internal_user
          else
            {:ok, me} =
              Accounts.ensure_user(%{
                platform_id: to_string(user.id),
                platform: "discord",
                username: user.username
              })

            me
          end

        {items, total} =
          Collection.list_user_inventory(user_record.id, page: 1, sort: :rarity_level_name)

        targeting_other? = get_option(i.data.options, "user") != nil

        if total == 0 do
          %{type: 4, data: %{content: "#{user_name(tgt)}'s collection is empty."}}
        else
          embed =
            Embeds.collection_embed(items, 1, total, :rarity_level_name, tgt.discord_user || user)

          if targeting_other? do
            %{type: 4, data: %{embeds: [embed]}}
          else
            components = Components.collection_components(1, total, :rarity_level_name)
            %{type: 4, data: %{embeds: [embed], components: components}}
          end
        end
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
      {:ok, m} ->
        items_text =
          if Enum.empty?(m.items) do
            ""
          else
            " You also received: " <> Enum.map_join(m.items, ", ", & &1.name)
          end

        hours =
          if m.mining_seconds > 0,
            do: Float.round(m.mining_seconds / 3600.0, 2) |> to_string(),
            else: "0"

        cap_h = Float.round(m.mining_cap_seconds / 3600.0, 1) |> to_string()

        mining_line =
          cond do
            m.mining_roster_size == 0 ->
              "Mining: **#{m.mining_coins}** #{Currency.coin_emoji()} (no roster — use `/mines add`)."

            m.mining_coins > 0 ->
              "Mining: **#{m.mining_coins}** #{Currency.coin_emoji()} (~#{hours}h toward **#{cap_h}h** cap)."

            true ->
              "Mining: **0** #{Currency.coin_emoji()} (roster set; accrual window was empty or capped)."
          end

        content =
          "You claimed your daily reward!\n" <>
            "Streak bonus: **#{m.streak_coins}** #{Currency.coin_emoji()} · Streak **#{m.streak}** days.\n" <>
            mining_line <>
            "\n**Total today: #{m.coins}** #{Currency.coin_emoji()}" <>
            items_text

        %{type: 4, data: %{content: content}}

      {:error, reason} ->
        %{type: 4, data: %{content: "Could not claim daily reward: #{reason}"}}
    end
  end

  def handle_command("balance", i) do
    user = i.user || i.member.user

    {:ok, ur} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    dust = ur.dust || 0

    roster_lines =
      case MineRoster.view(ur.id) do
        {:ok, names} ->
          if names == [] do
            "_Empty — add marbles with `/mines add`._"
          else
            names |> Enum.with_index(1) |> Enum.map_join("\n", fn {n, idx} -> "#{idx}. #{n}" end)
          end

        _ ->
          "_Unknown_"
      end

    content =
      "**Wallet**\n#{Embeds.currency_line(ur.currency)} · **#{dust}** #{Currency.dust_emoji()}\n\n" <>
        "**Mine roster** (max 5)\n#{roster_lines}"

    %{type: 4, data: %{content: content}}
  end

  def handle_command("profile", i) do
    tgt = resolve_target(i, "user")

    cond do
      is_nil(tgt.internal_user) and get_option(i.data.options, "user") != nil ->
        %{type: 4, data: %{content: "That user does not have a profile."}}

      true ->
        user = i.user || i.member.user

        internal =
          if tgt.internal_user do
            tgt.internal_user
          else
            {:ok, me} =
              Accounts.ensure_user(%{
                platform_id: to_string(user.id),
                platform: "discord",
                username: user.username
              })

            me
          end

        {_items, total_collection} =
          Collection.list_user_inventory(internal.id, page: 1, per_page: 1)

        {:ok, roster_names} = MineRoster.view(internal.id)
        active_effects = Effects.list_active(internal.id)

        streak =
          case Marbles.Repo.get_by(Marbles.Schema.UserDailyStreak, user_id: internal.id) do
            nil -> %{current_streak: 0, longest_streak: 0}
            row -> row
          end

        effects_text =
          if active_effects == [] do
            "None"
          else
            Enum.map_join(active_effects, "\n", fn e ->
              "• #{e.effect_key} (until #{Calendar.strftime(e.expires_at, "%Y-%m-%d %H:%M UTC")})"
            end)
          end

        roster_text =
          if roster_names == [] do
            "Empty"
          else
            Enum.join(roster_names, ", ")
          end

        title = display_name(tgt, internal)
        thumbnail_user = tgt.discord_user || tgt.invoker_discord_user
        thumbnail_url = thumbnail_user && Nostrum.Struct.User.avatar_url(thumbnail_user)

        embed =
          %Embed{}
          |> Embed.put_title(title)
          |> Embed.put_description(
            "Coins: **#{internal.currency}** #{Currency.coin_emoji()}\n" <>
              "Dust: **#{internal.dust}** #{Currency.dust_emoji()}\n" <>
              "Owned marbles: **#{total_collection}**\n" <>
              "Streak: **#{streak.current_streak}** (longest #{streak.longest_streak})\n" <>
              "Mine roster: #{roster_text}\n\n" <>
              "Active boosts/effects:\n#{effects_text}"
          )
          |> maybe_put_thumbnail(thumbnail_url)

        %{type: 4, data: %{embeds: [embed]}}
    end
  end

  def handle_command("boosts", i) do
    tgt = resolve_target(i, "user")

    if is_nil(tgt.internal_user) and get_option(i.data.options, "user") != nil do
      %{type: 4, data: %{content: "That user is not in the system yet."}}
    else
      user = i.user || i.member.user

      internal =
        if tgt.internal_user do
          tgt.internal_user
        else
          {:ok, me} =
            Accounts.ensure_user(%{
              platform_id: to_string(user.id),
              platform: "discord",
              username: user.username
            })

          me
        end

      active_effects = Effects.list_active(internal.id)

      text =
        if active_effects == [] do
          "No active boosts."
        else
          Enum.map_join(active_effects, "\n", fn e ->
            "• **#{e.effect_key}** · expires #{Calendar.strftime(e.expires_at, "%Y-%m-%d %H:%M UTC")}"
          end)
        end

      %{type: 4, data: %{content: "**#{user_name(tgt)} active boosts**\n#{text}", flags: 64}}
    end
  end

  def handle_command("leaderboard", i) do
    kind = get_option(i.data.options, "kind") || "coins"

    rows =
      case kind do
        "collection" -> Leaderboards.top_collection_count(10)
        "strongest" -> Leaderboards.top_strongest_marble(10)
        _ -> Leaderboards.top_coins(10)
      end

    title =
      case kind do
        "collection" -> "Top collections"
        "strongest" -> "Strongest marble (level score)"
        _ -> "Richest players"
      end

    body =
      if rows == [] do
        "No entries yet."
      else
        Enum.map_join(rows, "\n", fn r ->
          "#{r.rank}. **#{r.label}** — #{r.score}"
        end)
      end

    embed =
      %Embed{}
      |> Embed.put_title(title)
      |> Embed.put_description(body)

    %{type: 4, data: %{embeds: [embed]}}
  end

  def handle_command("mines", i) do
    user = i.user || i.member.user

    {:ok, ur} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {sub, opts} = first_subcommand(i)

    case sub do
      "view" ->
        case MineRoster.view(ur.id) do
          {:ok, names} ->
            lines =
              if names == [] do
                "Roster is empty. Add up to 5 marbles with `/mines add`."
              else
                names
                |> Enum.with_index(1)
                |> Enum.map_join("\n", fn {n, idx} -> "#{idx}. #{n}" end)
              end

            %{type: 4, data: %{content: "**Mine roster**\n#{lines}", flags: 64}}

          _ ->
            %{type: 4, data: %{content: "Could not load roster.", flags: 64}}
        end

      "add" ->
        marble = get_option(opts, "marble") || ""

        case MineRoster.add_by_marble_name(ur.id, marble) do
          {:ok, %{slots: n}} ->
            %{
              type: 4,
              data: %{content: "**#{marble}** Added to roster (**#{n}/5**).", flags: 64}
            }

          {:error, :roster_full} ->
            %{
              type: 4,
              data: %{content: "Roster is full (5). Remove one with `/mines remove`.", flags: 64}
            }

          {:error, :already_in_roster} ->
            %{type: 4, data: %{content: "**#{marble}** is already in your roster.", flags: 64}}

          {:error, :not_found} ->
            %{
              type: 4,
              data: %{content: "No owned marble matched the name **#{marble}**.", flags: 64}
            }

          {:error, :invalid_name} ->
            %{type: 4, data: %{content: "Provide a marble name.", flags: 64}}
        end

      "remove" ->
        marble = get_option(opts, "marble") || ""

        case MineRoster.remove_by_marble_name(ur.id, marble) do
          {:ok, %{slots: n}} ->
            %{
              type: 4,
              data: %{content: "**#{marble}** removed from roster (**#{n}/5**).", flags: 64}
            }

          {:error, :not_found} ->
            %{
              type: 4,
              data: %{content: "No roster entry matched the name **#{marble}**.", flags: 64}
            }

          {:error, :invalid_name} ->
            %{type: 4, data: %{content: "Provide a marble name.", flags: 64}}
        end

      "clear" ->
        {:ok, _} = MineRoster.clear(ur.id)
        %{type: 4, data: %{content: "Mine roster cleared.", flags: 64}}

      _ ->
        %{
          type: 4,
          data: %{
            content: "Use `/mines view`, `/mines add`, `/mines remove`, or `/mines clear`.",
            flags: 64
          }
        }
    end
  end

  def handle_command("upgrades", i) do
    user = i.user || i.member.user

    {:ok, ur} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {sub, opts} = first_subcommand(i)

    case sub do
      "view" ->
        lines =
          Upgrades.definitions()
          |> Enum.map_join("\n", fn {k, v} ->
            lv = Upgrades.level(ur.id, k)

            next =
              if lv >= v.max_level,
                do: "MAX",
                else: "#{Enum.at(v.costs, lv)} #{Currency.dust_emoji()}"

            "• **#{v.title}** — Lv.#{lv}/#{v.max_level} — next: #{next}"
          end)

        %{type: 4, data: %{content: "**Upgrades**\n#{lines}", flags: 64}}

      "buy" ->
        key = get_option(opts, "upgrade") || ""
        defs = Upgrades.definitions()
        lv = Upgrades.level(ur.id, key)
        defn = defs[key]
        need = if defn && lv < defn.max_level, do: Enum.at(defn.costs, lv), else: nil

        case Upgrades.buy(ur.id, key) do
          {:ok, %{new_level: nl}} ->
            title = get_in(defs, [key, :title]) || key
            fresh = Accounts.get_user!(ur.id)

            %{
              type: 4,
              data: %{
                content:
                  "Upgraded **#{title}** to level **#{nl}**.\nRemaining dust: **#{fresh.dust}** #{Currency.dust_emoji()}",
                flags: 64
              }
            }

          {:error, :invalid_key} ->
            %{type: 4, data: %{content: "Unknown upgrade key.", flags: 64}}

          {:error, :maxed} ->
            %{type: 4, data: %{content: "That upgrade is already maxed.", flags: 64}}

          {:error, :insufficient_dust} ->
            need_text = if is_integer(need), do: to_string(need), else: "?"

            %{
              type: 4,
              data: %{
                content:
                  "Not enough dust. Needed **#{need_text}** #{Currency.dust_emoji()}, you have **#{ur.dust}** #{Currency.dust_emoji()}.",
                flags: 64
              }
            }
        end

      _ ->
        %{type: 4, data: %{content: "Use `/upgrades view` or `/upgrades buy`.", flags: 64}}
    end
  end

  def handle_command("shop", i) do
    user = i.user || i.member.user

    {:ok, ur} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {sub, opts} = first_subcommand(i)

    case sub do
      "list" ->
        lines =
          Shop.products()
          |> Enum.map_join("\n", fn p ->
            used = Shop.purchases_in_period(ur.id, p)
            max_count = p.limit_count || 3
            period = Shop.period_label(p.limit_period_unit || "week")
            price = price_line(p)
            "• **#{p.name}** — #{price} — bought this #{period}: **#{used}/#{max_count}**"
          end)

        %{type: 4, data: %{content: "**Shop**\n#{lines}", flags: 64}}

      "buy" ->
        pid = get_option(opts, "product") || ""
        product = Enum.find(Shop.products(), &(&1.id == pid))

        case Shop.buy(ur.id, pid) do
          {:ok, _effect} ->
            fresh = Accounts.get_user!(ur.id)

            product =
              Shop.products()
              |> Enum.find(&(&1.id == pid))

            title = if product, do: product.name, else: pid
            duration = if product, do: format_duration(product.duration_sec), else: "?"

            %{
              type: 4,
              data: %{
                content:
                  "Purchased **#{title}**. Effect lasts **#{duration}**.\nWallet now: **#{fresh.currency}** #{Currency.coin_emoji()} · **#{fresh.dust}** #{Currency.dust_emoji()}",
                flags: 64
              }
            }

          {:error, :invalid_product} ->
            %{type: 4, data: %{content: "Unknown product.", flags: 64}}

          {:error, :period_limit} ->
            %{
              type: 4,
              data: %{content: "Purchase limit reached for the current period.", flags: 64}
            }

          {:error, :insufficient_coins} ->
            need = if product, do: product.coin, else: nil
            need_text = if is_integer(need), do: to_string(need), else: "?"

            %{
              type: 4,
              data: %{
                content:
                  "Not enough coins. Needed **#{need_text}** #{Currency.coin_emoji()}, you have **#{ur.currency}** #{Currency.coin_emoji()}.",
                flags: 64
              }
            }

          {:error, :insufficient_dust} ->
            need = if product, do: product.dust, else: nil
            need_text = if is_integer(need), do: to_string(need), else: "?"

            %{
              type: 4,
              data: %{
                content:
                  "Not enough dust. Needed **#{need_text}** #{Currency.dust_emoji()}, you have **#{ur.dust}** #{Currency.dust_emoji()}.",
                flags: 64
              }
            }
        end

      _ ->
        %{type: 4, data: %{content: "Use `/shop list` or `/shop buy`.", flags: 64}}
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
