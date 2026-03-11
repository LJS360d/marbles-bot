defmodule MarblesDiscordbot.Consumers.Interaction do
  use Nostrum.Consumer
  alias Logger
  alias Nostrum.Struct.Interaction
  alias Nostrum.Api
  alias Marbles.Catalog

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

    user = i.user || i.member.user
    Logger.info("From user '#{user.username}' in #{location}: /#{i.data.name}")

    response = handle_command(i.data.name, i)

    if response do
      case Api.create_interaction_response(i, response) do
        {:ok} -> :ok
        {:error, err} -> Logger.error("Interaction response failed: #{inspect(err)}")
      end
    end
  end

  def handle_event(_), do: :ok

  defp handle_command("packs", _i) do
    packs = Catalog.list_active_packs()

    content =
      if packs == [] do
        "No packs are currently available."
      else
        lines =
          Enum.map(packs, fn p ->
            count = length(p.marbles || [])
            "**#{p.name}** — #{p.cost} coins · #{count} marbles"
          end)

        "**Available packs**\n" <> Enum.join(lines, "\n")
      end

    %{type: 4, data: %{content: content}}
  end

  defp handle_command("spawnrate", i) do
    spawnrate = i.data.options |> Enum.find(fn o -> o.name == "spawnrate" end) |> Map.get(:value)

    case spawnrate do
      # respond to the interaction with the current spawnrate
      nil ->
        %{type: 4, data: %{content: ""}}

      # set the spawnrate to n in db
      n ->
        %{type: 4, data: %{content: "Spawnrate set to #{n}"}}
    end
  end

  defp handle_command(_, _), do: nil
end
