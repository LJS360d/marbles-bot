defmodule Marbles.Racing.Engine.Registry do
  @moduledoc "`Registry` for race engine GenServers, keyed by race_id."

  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end
