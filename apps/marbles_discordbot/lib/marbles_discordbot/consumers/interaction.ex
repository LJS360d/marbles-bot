defmodule MarblesDiscordbot.Consumers.Interaction do
  use Nostrum.Consumer
  alias Logger
  alias Nostrum.Struct.Interaction
  # alias Nostrum.Struct.ApplicationCommandInteractionData

  def handle_event({:INTERACTION_CREATE, %Interaction{} = i, _ws_state}) do
    location =
      if i.guild_id do
        case Nostrum.Cache.GuildCache.get(i.guild_id) do
          {:ok, guild} -> "guild: '#{guild.name}'"
          _ -> "Unknown Guild"
        end
      else
        "DMs"
      end

    # Nostrum uses i.user for DMs and i.member.user for Guilds.
    user = i.user || i.member.user
    Logger.info("From user '#{user.username}' in #{location}: /#{i.data.name}")
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
