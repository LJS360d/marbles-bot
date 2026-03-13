defmodule Marbles.Broadcast do
  @moduledoc """
  Broadcasts messages to Discord via PubSub. The bot subscribes and sends to guilds.
  """
  def send_announcement(message, guild_ids \\ :all) do
    Phoenix.PubSub.broadcast(
      Marbles.PubSub,
      "discord_announcement",
      %{message: message, guild_ids: guild_ids}
    )
  end
end
