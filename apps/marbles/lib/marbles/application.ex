defmodule Marbles.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Marbles.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:marbles, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:marbles, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Marbles.PubSub},
      Marbles.Racing.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Marbles.Supervisor)
  end

  defp skip_migrations? do
    Code.ensure_loaded?(Mix)
  end
end
