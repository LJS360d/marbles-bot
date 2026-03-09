defmodule MarblesDiscordbot.Consumers.Ready do
  use Nostrum.Consumer
  alias MarblesDiscordbot.Commands

  # This fires EXACTLY once when the bot is ready
  def handle_event({:READY, _data, _ws_state}) do
    Commands.sync()
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
