defmodule MarblesDiscordbot.Commands do
  alias Nostrum.Api.ApplicationCommand
  require Logger

  @commands [
    %{
      name: "pull",
      description: "Pull a random marble!",
      # ChatInput (Slash Command)
      type: 1
    },
    %{
      name: "trade",
      description: "Trade a marble with another user",
      # Guild-only
      dm_permission: false,
      options: [
        %{
          # USER type
          type: 6,
          name: "target",
          description: "The user you want to trade with",
          required: true
        }
      ]
    },
    %{
      name: "packs",
      description: "Show currently available packs",
      type: 1
    },
    %{
      name: "analytics",
      description: "Show analytics about the bot",
      type: 1
    }
  ]

  defp needs_resync?(remote, local) do
    if length(remote) != length(local) do
      true
    else
      local_names = local |> Enum.map(& &1.name) |> Enum.sort()
      remote_names = remote |> Enum.map(& &1.name) |> Enum.sort()

      if local_names != remote_names do
        true
      end

      # TODO better diffing

      false
    end
  end

  def sync do
    case ApplicationCommand.global_commands() do
      {:ok, remote_commands} ->
        if needs_resync?(remote_commands, @commands) do
          Logger.info("Syncing slash command interactions...")

          case ApplicationCommand.bulk_overwrite_global_commands(@commands) do
            {:ok, _} -> Logger.info("Commands synced successfully.")
            {:error, reason} -> Logger.error("Failed to sync commands: #{inspect(reason)}")
          end
        else
          Logger.info("Slash commands are up to date. Skipping sync.")
        end

      {:error, _} ->
        Logger.error("Could not verify commands")
    end
  end
end
