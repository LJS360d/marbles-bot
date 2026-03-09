defmodule MarblesDiscordbot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # 3. Start your Consumer process
      MarblesDiscordbot.Consumers.Ready,
      MarblesDiscordbot.Consumers.Message,
      MarblesDiscordbot.Consumers.Interaction
      # {Nostrum.Bot, bot_config}
    ]

    opts = [strategy: :one_for_one, name: MarblesDiscordbot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
