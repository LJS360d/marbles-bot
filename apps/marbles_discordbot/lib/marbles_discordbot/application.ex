defmodule MarblesDiscordbot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MarblesDiscordbot.PendingSpawns,
      MarblesDiscordbot.CommandsResyncSubscriber,
      MarblesDiscordbot.Consumers.Ready,
      MarblesDiscordbot.Consumers.Message,
      MarblesDiscordbot.Consumers.Reaction,
      MarblesDiscordbot.Consumers.Interaction,
      MarblesDiscordbot.Consumers.Component
    ]

    opts = [strategy: :one_for_one, name: MarblesDiscordbot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
