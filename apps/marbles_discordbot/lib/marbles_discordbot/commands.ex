defmodule MarblesDiscordbot.Commands do
  alias Nostrum.Api.ApplicationCommand
  alias Nostrum.Constants.ApplicationCommandOptionType
  alias Marbles.Catalog
  require Logger

  def commands do
    packs_choices =
      Catalog.list_active_packs(Date.utc_today(), :name)
      |> Enum.map(fn pack -> %{name: pack.name, value: to_string(pack.id)} end)

    [
      %{
        name: "pull",
        description: "Pull a random marble from a pack",
        options: [
          %{
            type: ApplicationCommandOptionType.string(),
            name: "pack",
            description: "The pack you want to pull from",
            required: true,
            choices: packs_choices
          }
        ]
      },
      %{
        name: "trade",
        description: "Trade with another user",
        # Guild-only
        dm_permission: false,
        options: [
          %{
            type: ApplicationCommandOptionType.user(),
            name: "target",
            description: "The user you want to trade with",
            required: true
          }
        ]
      },
      %{
        name: "spawnrate",
        description: "Manage marble spawn rates",
        dm_permission: false,
        options: [
          # Subcommand 1: View all
          %{
            type: ApplicationCommandOptionType.sub_command(),
            name: "list",
            description: "List spawn rates for all visible channels"
          },
          # Subcommand 2: Set rates
          %{
            type: ApplicationCommandOptionType.sub_command(),
            name: "set",
            description: "Set the spawn rate for specific channels",
            options: [
              %{
                type: ApplicationCommandOptionType.number(),
                name: "rate",
                description: "The rate in % (0-100)",
                required: true,
                min_value: 0.0,
                max_value: 100.0
              },
              %{
                type: ApplicationCommandOptionType.channel(),
                name: "channel",
                description: "Optional: Specific channel to update (defaults to current)",
                required: false
              }
            ]
          }
        ]
      },
      %{
        name: "collection",
        description: "See your marbles collection",
        type: 1
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
      },
      %{
        name: "daily",
        description: "Claim your daily reward and build your streak",
        type: 1
      }
    ]
  end

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
        if needs_resync?(remote_commands, commands()) do
          Logger.info("Syncing slash command interactions...")

          case sync_force() do
            {:ok, _} ->
              Logger.info("Commands synced successfully.")

            {:error, reason} ->
              Logger.error("Failed to sync commands: #{inspect(reason)}")
          end
        else
          Logger.info("Slash commands are up to date. Skipping sync.")
        end

      {:error, _} ->
        Logger.error("Could not verify commands")
    end
  end

  def sync_force do
    ApplicationCommand.bulk_overwrite_global_commands(commands())
  end
end
