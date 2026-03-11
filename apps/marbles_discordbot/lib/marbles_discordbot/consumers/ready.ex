defmodule MarblesDiscordbot.Consumers.Ready do
  use Nostrum.Consumer
  alias Nostrum.Shard
  alias MarblesDiscordbot.Commands

  # This fires once when the bot is ready
  def handle_event({:READY, _data, _ws_state}) do
    Commands.sync()

    guilds_count =
      case Nostrum.Api.Self.guilds() do
        {:ok, guilds} ->
          length(guilds)

        {:error, _} ->
          0
      end

    Shard.Supervisor.update_status(:online, "#{guilds_count} servers", nil, 3)
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
