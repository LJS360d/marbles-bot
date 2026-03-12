defmodule MarblesDiscordbot.Consumers.Reaction do
  use Nostrum.Consumer
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Event.MessageReactionAdd
  alias Nostrum.Api
  alias Marbles.{Accounts, Collection, Catalog}
  alias MarblesDiscordbot.{PendingSpawns}
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

      Collection.add_marble_to_collection(user_record.id, marble.id)

      embed =
        %Embed{}
        |> Embed.put_title("You got a #{marble.name}!")
        |> Embed.put_description("it's been added to your `/collection`")
        |> Embed.put_footer("Collected by #{event.member.nick}", "")

      case Api.Message.edit(event.channel_id, event.message_id, %{
             content: "",
             embeds: [embed]
           }) do
        {:ok, _} ->
          :ok

        err ->
          Logger.error("Failed to edit message: #{inspect(err)}")
      end

      PendingSpawns.delete_by_message(to_string(event.message_id))
    end

    :ok
  end

  def handle_event(_), do: :ok

  defp get_username(user_id) do
    case Nostrum.Cache.UserCache.get(user_id) do
      {:ok, u} -> u.username || "Invalid Username"
      _ -> "Unknown Username"
    end
  end
end
