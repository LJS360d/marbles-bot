defmodule MarblesDiscordbot.Commands do
  alias Nostrum.Api.ApplicationCommand
  alias Nostrum.Constants.ApplicationCommandOptionType
  alias Nostrum.Constants.ApplicationCommandType
  alias Marbles.Catalog
  alias Marbles.Economy.{Shop, Upgrades}
  require Logger

  @spec commands() :: [map()]
  def commands do
    packs_choices =
      Catalog.list_active_packs(Date.utc_today(), :name)
      |> Enum.map(fn pack -> %{name: pack.name, value: to_string(pack.id)} end)

    chat_input_commands =
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
          type: 1,
          options: [optional_user_option()]
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
        },
        %{
          name: "balance",
          description: "Show your coins, dust, and mine roster",
          type: 1
        },
        %{
          name: "profile",
          description: "Show a user profile (wallet, collection, boosts, mines)",
          type: 1,
          options: [optional_user_option()]
        },
        %{
          name: "boosts",
          description: "Show active boosts",
          type: 1,
          options: [optional_user_option()]
        },
        %{
          name: "leaderboard",
          description: "Show top players",
          options: [
            %{
              type: ApplicationCommandOptionType.string(),
              name: "kind",
              description: "Leaderboard to show",
              required: false,
              choices: [
                %{name: "Coins", value: "coins"},
                %{name: "Collection size", value: "collection"}
              ]
            }
          ]
        },
        %{
          name: "mines",
          description: "Manage marbles assigned to passive coin mining",
          options: [
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "view",
              description: "Show roster"
            },
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "add",
              description: "Add a marble you own (exact name, case-insensitive)",
              options: [required_marble_name_option()]
            },
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "remove",
              description: "Remove a roster marble by name",
              options: [required_marble_name_option()]
            },
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "clear",
              description: "Clear roster"
            }
          ]
        },
        %{
          name: "upgrades",
          description: "Spend dust on permanent account upgrades",
          options: [
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "view",
              description: "List upgrades"
            },
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "buy",
              description: "Buy the next level of an upgrade (costs dust)",
              options: [
                %{
                  type: ApplicationCommandOptionType.string(),
                  name: "upgrade",
                  description: "Upgrade to buy",
                  required: true,
                  choices:
                    Upgrades.definitions()
                    |> Enum.map(fn {k, v} ->
                      %{name: String.slice(v.title, 0, 100), value: k}
                    end)
                }
              ]
            }
          ]
        },
        %{
          name: "shop",
          description: "Buy items and temporary boosts",
          options: [
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "list",
              description: "List offers"
            },
            %{
              type: ApplicationCommandOptionType.sub_command(),
              name: "buy",
              description: "Buy an item or boost",
              options: [
                %{
                  type: ApplicationCommandOptionType.string(),
                  name: "product",
                  description: "Product id",
                  required: true,
                  choices:
                    Shop.products()
                    |> Enum.map(fn p ->
                      %{name: String.slice(p.name, 0, 100), value: p.id}
                    end)
                }
              ]
            }
          ]
        }
      ]

    discord_activity_commands() ++ chat_input_commands
  end

  @discord_launch_activity_handler 2

  @spec discord_activity_commands() :: [map()]
  defp discord_activity_commands do
    discord_activity =
      Application.get_env(:marbles_discordbot, :discord_activity, [])
      |> Keyword.get(:enabled, false)

    if discord_activity do
      name =
        Application.get_env(:marbles_discordbot, :discord_activity, [])
        |> Keyword.get(:entry_command_name, "play")

      description =
        Application.get_env(:marbles_discordbot, :discord_activity, [])
        |> Keyword.get(:entry_command_description, "Open the Marbles embedded activity")

      [
        %{
          type: ApplicationCommandType.primary_entry_point(),
          name: name,
          description: description,
          handler: @discord_launch_activity_handler
        }
      ]
    else
      []
    end
  end

  @spec optional_user_option() :: map()
  defp optional_user_option do
    %{
      type: ApplicationCommandOptionType.user(),
      name: "user",
      description: "Optional target user",
      required: false
    }
  end

  @spec required_marble_name_option() :: map()
  defp required_marble_name_option do
    %{
      type: ApplicationCommandOptionType.string(),
      name: "marble",
      description: "Marble name",
      required: true,
      autocomplete: true
    }
  end

  @spec command_type(map()) :: pos_integer()
  defp command_type(cmd) when is_map(cmd) do
    raw = Map.get(cmd, :type, Map.get(cmd, "type", ApplicationCommandType.chat_input()))

    cond do
      is_integer(raw) ->
        raw

      is_binary(raw) ->
        case Integer.parse(String.trim(raw)) do
          {int, ""} -> int
          _ -> ApplicationCommandType.chat_input()
        end

      true ->
        ApplicationCommandType.chat_input()
    end
  end

  defp command_type(_), do: ApplicationCommandType.chat_input()

  @spec remote_chat_input_commands([map()]) :: [map()]
  defp remote_chat_input_commands(remote) do
    Enum.reject(remote, &(command_type(&1) == ApplicationCommandType.primary_entry_point()))
  end

  @spec entry_point_signature(map()) ::
          {String.t(), pos_integer(), String.t(), pos_integer() | nil}
  defp entry_point_signature(cmd) when is_map(cmd) do
    name = Map.get(cmd, :name) || Map.get(cmd, "name") || ""
    desc = Map.get(cmd, :description) || Map.get(cmd, "description") || ""

    handler =
      case Map.get(cmd, :handler, Map.get(cmd, "handler")) do
        int when is_integer(int) ->
          int

        bin when is_binary(bin) ->
          case Integer.parse(String.trim(bin)) do
            {int, ""} -> int
            _ -> nil
          end

        _ ->
          nil
      end

    {name, command_type(cmd), desc, handler}
  end

  @spec needs_resync?([map()], [map()]) :: boolean()
  defp needs_resync?(remote, local) do
    remote_chat = remote_chat_input_commands(remote)

    remote_chat_names =
      remote_chat
      |> Enum.map(fn cmd -> Map.get(cmd, :name) || Map.get(cmd, "name") end)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.sort()

    local_chat =
      Enum.reject(local, &(command_type(&1) == ApplicationCommandType.primary_entry_point()))

    local_chat_names = local_chat |> Enum.map(& &1.name) |> Enum.sort()

    remote_entry_points =
      remote |> Enum.filter(&(command_type(&1) == ApplicationCommandType.primary_entry_point()))

    local_entry_points =
      local |> Enum.filter(&(command_type(&1) == ApplicationCommandType.primary_entry_point()))

    remote_entry_sigs =
      remote_entry_points
      |> Enum.map(&entry_point_signature/1)
      |> Enum.sort()

    local_entry_sigs =
      local_entry_points
      |> Enum.map(&entry_point_signature/1)
      |> Enum.sort()

    cond do
      length(remote_chat) != length(local_chat) -> true
      remote_chat_names != local_chat_names -> true
      remote_entry_sigs != local_entry_sigs -> true
      true -> false
    end
  end

  @spec sync() :: :ok
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

  @spec sync_force() :: {:ok, any()} | {:error, any()}
  def sync_force do
    local = commands()

    case ApplicationCommand.global_commands() do
      {:ok, remote} ->
        activity_enabled =
          Application.get_env(:marbles_discordbot, :discord_activity, [])
          |> Keyword.get(:enabled, false)

        merged =
          if activity_enabled do
            local_entry_names =
              local
              |> Enum.filter(&(command_type(&1) == ApplicationCommandType.primary_entry_point()))
              |> Enum.map(& &1.name)
              |> MapSet.new()

            preserved_remote_entry_points =
              remote
              |> Enum.filter(&(command_type(&1) == ApplicationCommandType.primary_entry_point()))
              |> Enum.reject(fn cmd ->
                name = Map.get(cmd, :name) || Map.get(cmd, "name")
                name && MapSet.member?(local_entry_names, name)
              end)
              |> Enum.map(&Map.drop(&1, [:id, :version, :application_id, :guild_id]))

            local ++ preserved_remote_entry_points
          else
            local
          end

        ApplicationCommand.bulk_overwrite_global_commands(merged)

      {:error, _} = err ->
        err
    end
  end
end
