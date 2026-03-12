defmodule MarblesDiscordbot.Consumers.Message do
  use Nostrum.Consumer
  alias Marbles.Schema.Channel
  alias Nostrum.Struct.Message
  alias Nostrum.Api
  alias Marbles.{Guilds, Gacha, Catalog, Analytics}
  alias MarblesDiscordbot.{PendingSpawns, Embeds}
  require Logger

  @spawn_emoji_pool ["✨", "🔥", "🔴"]

  # Ignore messages from bots (required to avoid infinite loops)
  def handle_event({:MESSAGE_CREATE, %Message{author: %{bot: true}}, _ws_state}), do: :ok

  # Ignore messages without a channel_id or guild_id
  def handle_event({:MESSAGE_CREATE, %Message{channel_id: nil}, _ws_state}), do: :ok
  def handle_event({:MESSAGE_CREATE, %Message{guild_id: nil}, _ws_state}), do: :ok

  def handle_event({:MESSAGE_CREATE, %Message{} = msg, _ws_state}) do
    channel_id_str = to_string(msg.channel_id)

    with %Channel{} = channel <- Guilds.get_channel(channel_id_str),
         true <- channel.spawn_rate > 0,
         true <- :rand.uniform(100) - 1 < channel.spawn_rate do
      guild_id_str = to_string(msg.guild_id)

      case Gacha.spawn_marble(guild_id_str, channel_id_str) do
        {:ok, spawned} ->
          marble = Catalog.get_marble!(spawned.id)
          emoji = Enum.random(@spawn_emoji_pool)

          embed =
            Embeds.marble_embed(marble, footer: "React with #{emoji} to collect this marble!")

          case Api.Message.create(msg.channel_id, %{
                 content: "A marble has spawned!",
                 embeds: [embed]
               }) do
            {:ok, created} ->
              expires = DateTime.utc_now() |> DateTime.add(300, :second)

              PendingSpawns.create(
                to_string(created.id),
                channel_id_str,
                marble.id,
                emoji,
                expires
              )

              Analytics.record_spawn(guild_id_str, channel_id_str, nil, %{
                "marble_id" => to_string(marble.id)
              })

            {:error, err} ->
              Logger.error("Discord API Error: #{inspect(err, pretty: true)}")
          end

        {:error, err} ->
          Logger.error("Gacha Spawn Error: #{inspect(err, pretty: true)}")
      end
    else
      # Silently ignore if channel not found or spawn roll fails
      _ -> :ok
    end
  end

  # Catch-all for other events
  def handle_event(_), do: :ok
end
