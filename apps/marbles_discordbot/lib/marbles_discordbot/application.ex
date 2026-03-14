defmodule MarblesDiscordbot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Horde Registry
      {Horde.Registry, [name: MarblesDiscordbot.HordeRegistry, keys: :unique, members: :auto]},

      #  Horde Supervisor
      {Horde.DynamicSupervisor,
       [name: MarblesDiscordbot.HordeSupervisor, strategy: :one_for_one, members: :auto]},

      # Subscriber for resyncing commands
      MarblesDiscordbot.CommandsResyncSubscriber,

      # Discord Consumers
      MarblesDiscordbot.Consumers.Events,
      MarblesDiscordbot.Consumers.Message,
      MarblesDiscordbot.Consumers.Reaction,
      MarblesDiscordbot.Consumers.Interaction,
      MarblesDiscordbot.Consumers.Component
    ]

    opts = [strategy: :one_for_one, name: MarblesDiscordbot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
