defmodule Marbles.Racing.Engine.UserIndex do
  @moduledoc """
  ETS-backed `user_id -> race_id` index for in-flight races.

  Populated by `Marbles.Racing.Engine.init/1` when a race spawns and cleared
  by the engine's `terminate/2` on any exit (normal finish, timeout, crash).
  Lookup is read-concurrent.
  """

  use GenServer

  @table :marbles_engine_user_race

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @spec put(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def put(user_id, race_id) do
    :ets.insert(@table, {user_id, race_id})
    :ok
  end

  @spec put_many([Ecto.UUID.t()], Ecto.UUID.t()) :: :ok
  def put_many(user_ids, race_id) do
    Enum.each(user_ids, &put(&1, race_id))
  end

  @spec remove_race(Ecto.UUID.t()) :: :ok
  def remove_race(race_id) do
    :ets.match_delete(@table, {:_, race_id})
    :ok
  end

  @spec find(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def find(user_id) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, race_id}] -> race_id
      _ -> nil
    end
  end

  @spec users_for(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def users_for(race_id) do
    :ets.match(@table, {:"$1", race_id}) |> List.flatten()
  end
end
