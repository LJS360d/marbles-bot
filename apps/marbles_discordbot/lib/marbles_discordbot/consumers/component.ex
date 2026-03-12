defmodule MarblesDiscordbot.Consumers.Component do
  use Nostrum.Consumer
  alias Nostrum.Struct.{Interaction, Embed}
  alias Nostrum.Api
  alias Marbles.{Catalog, Accounts, Collection, Gacha}
  alias MarblesDiscordbot.Embeds
  alias MarblesDiscordbot.Components
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

    response = handle_component(i, custom_id)

    if response do
      case Api.create_interaction_response(i, response) do
        {:ok} -> :ok
        {:error, err} -> Logger.error("Component interaction response failed: #{inspect(err)}")
      end
    end
  end

  defp handle_component(_i, "packs_prev_" <> rest) do
    page = String.to_integer(rest)
    packs = Catalog.list_active_packs(Date.utc_today(), :newest)
    new_page = max(0, page - 1)
    pack = Enum.at(packs, new_page)

    if pack do
      embed = Embeds.pack_embed(pack, new_page + 1, length(packs))
      components = Components.packs_nav_components(packs, new_page)
      %{type: 7, data: %{embeds: [embed], components: components}}
    else
      nil
    end
  end

  defp handle_component(_i, "packs_next_" <> rest) do
    page = String.to_integer(rest)
    packs = Catalog.list_active_packs(Date.utc_today(), :newest)
    new_page = min(length(packs) - 1, page + 1)
    pack = Enum.at(packs, new_page)

    if pack do
      embed = Embeds.pack_embed(pack, new_page + 1, length(packs))
      components = Components.packs_nav_components(packs, new_page)
      %{type: 7, data: %{embeds: [embed], components: components}}
    else
      nil
    end
  end

  defp handle_component(i, "packs_pull_" <> pack_id_str) do
    user = i.user || i.member.user

    {:ok, user_record} =
      Accounts.ensure_user(%{
        platform_id: to_string(user.id),
        platform: "discord",
        username: user.username
      })

    case Ecto.UUID.cast(pack_id_str) do
      {:ok, pack_id} ->
        pack =
          Catalog.list_active_packs()
          |> Enum.find(fn p -> p.id == pack_id end)

        if pack == nil do
          %{type: 4, data: %{content: "That pack is not available."}}
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

                      embed = Embeds.marble_embed(marble)

                      embed =
                        embed
                        |> Embed.put_description(spoiler_wrap.(embed.description || ""))
                        |> Embed.put_title(spoiler_wrap.(embed.title || ""))

                      %{type: 4, data: %{embeds: [embed]}}

                    {:error, _} ->
                      %{
                        type: 4,
                        data: %{content: "Could not pull from this pack. Try again later."}
                      }
                  end
                else
                  %{
                    type: 4,
                    data: %{
                      content:
                        "You need **#{cost}** coins to pull from **#{pack.name}**. You have #{user_record.currency}.",
                      ephemeral: true
                    }
                  }
                end
              end

            :error ->
              %{type: 4, data: %{content: "Invalid pack."}}
          end
        end

      :error ->
        %{type: 4, data: %{content: "Invalid pack."}}
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
