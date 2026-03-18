defmodule MarblesDiscordbot.Consumers.Component do
  use Nostrum.Consumer
  alias Nostrum.Struct.{Interaction, Embed}
  alias Nostrum.Api
  alias Marbles.{Catalog, Accounts, Collection, Gacha, PackPullRules, Repo}
  alias Marbles.Schema.{User, Pack}
  alias MarblesDiscordbot.Embeds
  alias MarblesDiscordbot.Components
  alias MarblesDiscordbot.{PullButtons, PullSession}
  require Logger

  @collection_per_page Marbles.Collection.per_page()

  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{custom_id: custom_id}} = i, _ws_state}
      )
      when not is_nil(custom_id) do
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
    Logger.info("From user '#{user.username}' in #{location}: :#{custom_id}")

    response =
      case pull_try(i, custom_id) do
        {:ok, r} -> r
        :continue -> handle_component(i, custom_id)
      end

    case response do
      nil ->
        :ok

      {:deferred, fun} when is_function(fun, 0) ->
        case Api.create_interaction_response(i, %{type: 5}) do
          {:ok} ->
            _ = Task.start(fn -> fun.() end)
            :ok

          {:error, err} ->
            Logger.error("Defer interaction failed: #{inspect(err)}")
        end

      response ->
        case Api.create_interaction_response(i, response) do
          {:ok} -> :ok
          {:error, err} -> Logger.error("Component interaction response failed: #{inspect(err)}")
        end
    end
  end

  defp handle_component(i, "packs_prev_" <> rest) do
    {page, session_sid} = parse_packs_page_session(rest, i)
    packs = Catalog.list_active_packs(Date.utc_today(), :newest)
    new_page = max(0, page - 1)
    pack = Enum.at(packs, new_page)
    sid = session_sid_int(session_sid, i)

    if pack do
      embed = Embeds.pack_embed(pack, new_page + 1, length(packs))
      components = Components.packs_nav_components(packs, new_page, sid)
      %{type: 7, data: %{embeds: [embed], components: components}}
    else
      nil
    end
  end

  defp handle_component(i, "packs_next_" <> rest) do
    {page, session_sid} = parse_packs_page_session(rest, i)
    packs = Catalog.list_active_packs(Date.utc_today(), :newest)
    new_page = min(length(packs) - 1, page + 1)
    pack = Enum.at(packs, new_page)
    sid = session_sid_int(session_sid, i)

    if pack do
      embed = Embeds.pack_embed(pack, new_page + 1, length(packs))
      components = Components.packs_nav_components(packs, new_page, sid)
      %{type: 7, data: %{embeds: [embed], components: components}}
    else
      nil
    end
  end

  defp handle_component(i, "packs_open_" <> rest) do
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {pack_id, owner_sid} = parse_packs_open(rest, user.id)

    with {:ok, pid} <- Ecto.UUID.cast(pack_id),
         pack when not is_nil(pack) <-
           Enum.find(Catalog.list_active_packs(), fn p -> p.id == pid end) do
      if to_string(user.id) != to_string(owner_sid) do
        ephemeral_mention("Only <@#{owner_sid}> can open this pack’s pull session.", owner_sid)
      else
        owner_int = PullSession.discord_id(to_string(owner_sid))

        %{
          type: 4,
          data: %{
            content: Embeds.pull_session_message_content(user_record, pack),
            embeds: [Embeds.pull_banner_embed(pack)],
            components: PullSession.action_row(user_record, pack, owner_int)
          }
        }
      end
    else
      :error ->
        %{type: 4, data: %{content: "Invalid pack."}}

      nil ->
        %{type: 4, data: %{content: "That pack is not available."}}
    end
  end

  defp handle_component(i, "coll_prev_" <> rest) do
    [page_str, sort_str] = String.split(rest, "_", parts: 2)
    page = String.to_integer(page_str)
    sort = sort_atom(String.trim_leading(sort_str, ":"))
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {items, total} =
      Collection.list_user_inventory(user_record.id, page: max(1, page - 1), sort: sort)

    embed = Embeds.collection_embed(items, max(1, page - 1), total, sort, user)
    components = Components.collection_components(max(1, page - 1), total, sort)
    %{type: 7, data: %{embeds: [embed], components: components}}
  end

  defp handle_component(i, "coll_next_" <> rest) do
    [page_str, sort_str] = String.split(rest, "_", parts: 2)
    page = String.to_integer(page_str)
    sort = sort_atom(String.trim_leading(sort_str, ":"))
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {_, total} = Collection.list_user_inventory(user_record.id, page: 1, sort: sort)
    max_page = max(1, div(total - 1, @collection_per_page) + 1)
    new_page = min(max_page, page + 1)
    {items, total} = Collection.list_user_inventory(user_record.id, page: new_page, sort: sort)
    embed = Embeds.collection_embed(items, new_page, total, sort, user)
    components = Components.collection_components(new_page, total, sort)
    %{type: 7, data: %{embeds: [embed], components: components}}
  end

  defp handle_component(i, "coll_sort_rarity_1"),
    do: collection_sort_response(i, :rarity_level_name, 1)

  defp handle_component(i, "coll_sort_level_1"), do: collection_sort_response(i, :level_desc, 1)
  defp handle_component(i, "coll_sort_name_1"), do: collection_sort_response(i, :name_asc, 1)

  defp handle_component(_, _), do: nil

  defp pull_try(i, cid) do
    cond do
      String.starts_with?(cid, "pull10_") ->
        case PullButtons.parse(cid) do
          {:ok, 10, o, p} -> {:ok, pull_ten_deferred(i, o, p)}
          _ -> :continue
        end

      String.starts_with?(cid, "pull1_") ->
        case PullButtons.parse(cid) do
          {:ok, 1, o, p} -> {:ok, pull_one_deferred(i, o, p)}
          _ -> :continue
        end

      true ->
        :continue
    end
  end

  defp parse_packs_page_session(rest, i) do
    case String.split(rest, "_", parts: 2) do
      [p, sid] -> {String.to_integer(p), sid}
      [p] -> {String.to_integer(p), to_string((i.user || i.member.user).id)}
    end
  end

  defp session_sid_int(sid, i) do
    case Integer.parse(to_string(sid)) do
      {n, _} -> n
      :error -> (i.user || i.member.user).id
    end
  end

  defp parse_packs_open(rest, clicker_id) do
    case Regex.run(~r/^(.+)_(\d+)$/, rest) do
      [_, pack_str, sid] ->
        case Ecto.UUID.cast(pack_str) do
          {:ok, _} -> {pack_str, sid}
          :error -> {rest, to_string(clicker_id)}
        end

      nil ->
        {rest, to_string(clicker_id)}
    end
  end

  defp ephemeral_mention(content, mention_user_id) do
    uid = PullSession.discord_id(to_string(mention_user_id))

    %{
      type: 4,
      data: %{
        content: content,
        flags: 64,
        allowed_mentions: PullSession.user_mentions(uid)
      }
    }
  end

  defp app_id(%Interaction{application_id: id}) when not is_nil(id), do: id
  defp app_id(_), do: Nostrum.Cache.Me.get().id

  defp pull_one_deferred(i, owner_sid, pack_id) do
    u = i.user || i.member.user

    if to_string(u.id) != owner_sid do
      PullSession.wrong_owner_response(owner_sid)
    else
      {:ok, ur} = PullSession.ensure_discord_user(u.id, u.username)

      case PullSession.active_pack!(pack_id) do
        nil ->
          PullSession.pack_unavailable_response()

        pack ->
          q = PackPullRules.quote_one(ur.id, pack)

          if ur.currency < q.final_price do
            PullSession.insufficient_coins_response(q.final_price, ur.currency, "this pull")
          else
            {:deferred, fn -> exec_pull_one(i, pack, pack_id, ur, owner_sid, u) end}
          end
      end
    end
  end

  defp exec_pull_one(i, pack, pack_id, user_record, owner_sid, discord_user) do
    token = i.token
    aid = app_id(i)
    guild_id_str = i.guild_id && to_string(i.guild_id)
    owner_int = PullSession.discord_id(owner_sid)
    user_record = reload_user!(user_record.id)
    q = PackPullRules.quote_one(user_record.id, pack)

    if user_record.currency < q.final_price do
      _ =
        PullSession.followup_ephemeral(
          aid,
          token,
          insufficient_followup_text(q.final_price, user_record.currency, "this pull")
        )

      :ok
    else
      case gacha_pull_one(pack_id, user_record, q, guild_id_str) do
        {:ok, marble} ->
          internal = reload_user!(user_record.id)
          comps = PullSession.action_row(internal, pack, owner_int)
          PullSession.clear_components_on_message(i.message)

          emb = marble_spoiler_embed(marble, discord_user)

          _ =
            PullSession.followup_with_pull_row(
              aid,
              token,
              Embeds.pull_session_message_content(internal, pack),
              [emb],
              owner_int,
              comps
            )

          :ok

        {:error, _} ->
          _ =
            PullSession.followup_ephemeral(
              aid,
              token,
              "Could not pull from this pack. Try again later."
            )

          :ok
      end
    end
  rescue
    e ->
      Logger.error("pull1 async: #{Exception.format(:error, e, __STACKTRACE__)}")
      _ = PullSession.followup_ephemeral(app_id(i), i.token, "Pull failed. Try again.")
      :ok
  end

  defp pull_ten_deferred(i, owner_sid, pack_id) do
    u = i.user || i.member.user

    if to_string(u.id) != owner_sid do
      PullSession.wrong_owner_response(owner_sid)
    else
      {:ok, ur} = PullSession.ensure_discord_user(u.id, u.username)

      case PullSession.active_pack!(pack_id) do
        nil ->
          PullSession.pack_unavailable_response()

        pack ->
          q = PackPullRules.quote_ten(ur.id, pack)

          if ur.currency < q.final_price do
            PullSession.insufficient_coins_response(q.final_price, ur.currency, "this 10× pull")
          else
            {:deferred, fn -> exec_pull_ten(i, pack, pack_id, ur, owner_sid, u) end}
          end
      end
    end
  end

  defp exec_pull_ten(i, pack, pack_id, user_record, owner_sid, discord_user) do
    token = i.token
    aid = app_id(i)
    guild_id_str = i.guild_id && to_string(i.guild_id)
    owner_int = PullSession.discord_id(owner_sid)
    user_record = reload_user!(user_record.id)
    q = PackPullRules.quote_ten(user_record.id, pack)

    if user_record.currency < q.final_price do
      _ =
        PullSession.followup_ephemeral(
          aid,
          token,
          insufficient_followup_text(q.final_price, user_record.currency, "this 10× pull")
        )

      :ok
    else
      case gacha_pull_ten(pack_id, user_record, q, guild_id_str) do
        {:ok, marbles} ->
          internal = reload_user!(user_record.id)
          comps = PullSession.action_row(internal, pack, owner_int)
          PullSession.clear_components_on_message(i.message)

          emb = Embeds.ten_pull_result_embed(pack, marbles, discord_user)

          _ =
            PullSession.followup_with_pull_row(
              aid,
              token,
              Embeds.pull_session_message_content(internal, pack),
              [emb],
              owner_int,
              comps
            )

          :ok

        {:error, _} ->
          _ =
            PullSession.followup_ephemeral(
              aid,
              token,
              "Could not complete 10× pull. Try again later."
            )

          :ok
      end
    end
  rescue
    e ->
      Logger.error("pull10 async: #{Exception.format(:error, e, __STACKTRACE__)}")
      _ = PullSession.followup_ephemeral(app_id(i), i.token, "10× pull failed. Try again.")
      :ok
  end

  defp reload_user!(user_id), do: Repo.get!(User, user_id)

  defp insufficient_followup_text(needed, have, label) do
    "You need **#{needed}** coins for #{label}. You have #{have}."
  end

  defp gacha_pull_one(pack_id, %User{} = user_record, q, guild_id_str) do
    pack = Repo.get!(Pack, pack_id) |> Repo.preload(:pull_rules)
    mr = PackPullRules.pity_force_min_rarity(user_record.id, pack)
    opts = if mr, do: [min_rarity: mr], else: []

    case Gacha.pull_from_pack(pack_id, user_record.id, guild_id_str, opts) do
      {:ok, marble} ->
        PackPullRules.commit_pity_after_marble!(user_record.id, pack_id, marble.rarity)

        if q.final_price > 0 do
          {:ok, _} = Accounts.update_currency(user_record, -q.final_price)
        end

        PackPullRules.commit_after_one_pull!(user_record.id, pack_id, q)

        Collection.add_marble_to_collection(user_record.id, marble.id)
        {:ok, marble}

      {:error, _} = e ->
        e
    end
  end

  defp gacha_pull_ten(pack_id, %User{} = user_record, q, guild_id_str) do
    pack = Repo.get!(Pack, pack_id) |> Repo.preload(:pull_rules)

    result =
      Enum.reduce_while(1..10, [], fn _, acc ->
        mr = PackPullRules.pity_force_min_rarity(user_record.id, pack)
        opts = if mr, do: [min_rarity: mr], else: []

        case Gacha.pull_from_pack(pack_id, user_record.id, guild_id_str, opts) do
          {:ok, marble} ->
            PackPullRules.commit_pity_after_marble!(user_record.id, pack_id, marble.rarity)
            {:cont, [marble | acc]}

          {:error, _} = e ->
            {:halt, e}
        end
      end)

    case result do
      {:error, _} = e ->
        e

      marbles when is_list(marbles) ->
        marbles = Enum.reverse(marbles)

        if q.final_price > 0 do
          {:ok, _} = Accounts.update_currency(user_record, -q.final_price)
        end

        PackPullRules.commit_after_ten_pull!(user_record.id, pack_id, q)

        Enum.each(marbles, fn m ->
          Collection.add_marble_to_collection(user_record.id, m.id)
        end)

        {:ok, marbles}
    end
  end

  defp marble_spoiler_embed(marble, discord_user) do
    spoiler = fn t -> "|| " <> t <> " ||" end
    base = Embeds.marble_embed(marble)

    base
    |> Embed.put_description(spoiler.(base.description || ""))
    |> Embed.put_title(spoiler.(base.title || ""))
    |> Embed.put_footer("#{discord_user.global_name} · added to your collection")
  end

  defp sort_atom("rarity"), do: :rarity_level_name
  defp sort_atom("level"), do: :level_desc
  defp sort_atom("name"), do: :name_asc
  defp sort_atom(_), do: :rarity_level_name

  defp collection_sort_response(i, sort, page) do
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    {items, total} = Collection.list_user_inventory(user_record.id, page: page, sort: sort)
    embed = Embeds.collection_embed(items, page, total, sort, user)
    components = Components.collection_components(page, total, sort)
    %{type: 7, data: %{embeds: [embed], components: components}}
  end
end
