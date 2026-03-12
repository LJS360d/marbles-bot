defmodule MarblesDiscordbot.PendingSpawns do
  use GenServer

  @table :marbles_discordbot_pending_spawns

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create(message_id, channel_id, marble_id, emoji, expires_at) do
    GenServer.cast(__MODULE__, {:put, message_id, %{channel_id: channel_id, marble_id: marble_id, emoji: emoji, expires_at: expires_at}})
  end

  def get_by_message(message_id) do
    GenServer.call(__MODULE__, {:get, message_id})
  end

  def delete_by_message(message_id) do
    GenServer.cast(__MODULE__, {:delete, message_id})
  end

  @impl true
  def init(_opts) do
    tid = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{tid: tid}}
  end

  @impl true
  def handle_call({:get, message_id}, _from, state) do
    now = DateTime.utc_now()
    result =
      case :ets.lookup(state.tid, message_id) do
        [{^message_id, %{expires_at: expires_at} = entry}] ->
          if DateTime.compare(expires_at, now) == :gt do
            entry
          else
            :ets.delete(state.tid, message_id)
            nil
          end
        [] ->
          nil
      end
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:put, message_id, entry}, state) do
    :ets.insert(state.tid, {message_id, entry})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:delete, message_id}, state) do
    :ets.delete(state.tid, message_id)
    {:noreply, state}
  end
end
