defmodule MarblesDiscordbot.Consumers.Message do
  use Nostrum.Consumer

  alias Nostrum.Struct.Message

  def handle_event({:MESSAGE_CREATE, %Message{} = msg, _ws_state}) do
    IO.inspect(msg.content)
    # TODO roll a weighted dice, configurable at guild level
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
