defmodule Marbles.Racing.Supervisor do
  @moduledoc """
  Top-level supervisor for the racing subsystem.
  """

  use Supervisor

  alias Marbles.Racing.Engine
  alias Marbles.Racing.Events.{CronScheduler, Scheduler}
  alias Marbles.Racing.Queue

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(_opts), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    children = [
      {Task.Supervisor, name: Marbles.Racing.TaskSupervisor},
      Engine.Registry,
      Engine.UserIndex,
      Engine.Supervisor,
      Queue,
      Scheduler,
      CronScheduler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
