defmodule Marbles.Racing.Engine.Supervisor do
  @moduledoc """
  `DynamicSupervisor` for race engine processes.

  Public entry point: `start_race/1`.
  """

  use DynamicSupervisor

  alias Marbles.Racing.Engine
  alias Marbles.Racing.Engine.Setup

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_race(Setup.t()) :: DynamicSupervisor.on_start_child()
  def start_race(%Setup{} = setup) do
    DynamicSupervisor.start_child(__MODULE__, Engine.child_spec(setup))
  end
end
