defmodule MarblesDiscordbot.Consumers.Reaction do
  use Nostrum.Consumer
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Event.MessageReactionAdd
  alias Nostrum.Api
  alias Marbles.{Accounts, Catalog, SpawnCatch}
  alias Marbles.Economy.Currency
  alias MarblesDiscordbot.{PendingSpawns, Embeds}
  require Logger

  def handle_event({:MESSAGE_REACTION_ADD, %MessageReactionAdd{} = event, _ws_state}) do
    user_id = event.user_id
    pending = PendingSpawns.get_by_message(to_string(event.message_id))

    if pending && String.equivalent?(pending.emoji, event.emoji.name) do
      marble = Catalog.get_marble!(pending.marble_id)
      username = get_username(user_id)

      {:ok, user_record} =
        Accounts.ensure_user(%{
          platform_id: to_string(user_id),
          platform: "discord",
          username: username
        })

      spawn_rate = Map.get(pending, :spawn_rate, 0.0) * 1.0

      case SpawnCatch.collect(to_string(event.message_id), user_record.id, marble, spawn_rate) do
        {:error, :already_claimed} ->
          :ok

        {:ok, %{coins: coins, dust: dust, template: tpl}} ->
          {collection_line, duplicate_dust} =
            case tpl do
              {:new, _} ->
                {"Added to your `/collection`.", 0}

              {:duplicate, d, _} ->
                {"Already owned — **+#{d}** #{Currency.dust_emoji()} dust.", d}
            end

          rewards_line =
            if coins > 0 or dust > 0 do
              parts = [
                dust > 0 && "**+#{dust}** #{Currency.dust_emoji()}",
                coins > 0 && "**+#{coins}** #{Currency.coin_emoji()}"
              ]

              "Spawn rewards: " <>
                (parts
                 |> Enum.reject(&is_boolean/1)
                 |> Enum.join(" · ")) <> "\n"
            else
              ""
            end

          description = rewards_line <> collection_line
          total_dust = dust + duplicate_dust
          total_coins = coins

          collected_by =
            cond do
              match?(%{nick: _}, event.member) and is_binary(event.member.nick) and
                  event.member.nick != "" ->
                event.member.nick

              true ->
                username
            end

          content =
            if total_coins > 0 or total_dust > 0 do
              gains =
                [
                  total_dust > 0 && "+#{total_dust} #{Currency.dust_emoji()}",
                  total_coins > 0 && "+#{total_coins} #{Currency.coin_emoji()}"
                ]
                |> Enum.reject(&is_boolean/1)
                |> Enum.join(" · ")

              "<@#{user_id}> claimed this marble and gained #{gains}."
            else
              "<@#{user_id}> claimed this marble."
            end

          embed =
            Embeds.marble_embed(marble)
            |> Embed.put_title("You got a #{marble.name}!")
            |> Embed.put_description(description)
            |> Embed.put_footer("Collected by #{collected_by}", "")

          case Api.Message.edit(event.channel_id, event.message_id, %{
                 content: content,
                 embeds: [embed]
               }) do
            {:ok, _} ->
              PendingSpawns.delete_by_message(to_string(event.message_id))

            err ->
              Logger.error("Failed to edit message: #{inspect(err)}")
          end
      end
    end

    :ok
  end

  def handle_event(_), do: :ok

  defp get_username(user_id) do
    case Nostrum.Cache.UserCache.get(user_id) do
      {:ok, %{username: ""}} -> "Invalid Username"
      {:ok, %{username: username}} -> username
      _ -> "Unknown Username"
    end
  end
end
