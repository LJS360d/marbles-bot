defmodule MarblesDiscordbot.PendingSpawns do
  use GenServer, restart: :temporary

  alias MarblesDiscordbot.{HordeRegistry, HordeSupervisor}

  def create(message_id, channel_id, marble_id, emoji, expires_at) do
    data = %{
      channel_id: channel_id,
      marble_id: marble_id,
      emoji: emoji,
      expires_at: expires_at
    }

    # Start a process on the cluster and name it via the Horde Registry
    Horde.DynamicSupervisor.start_child(HordeSupervisor, %{
      id: {:spawn, message_id},
      start: {__MODULE__, :start_link, [message_id, data]},
      restart: :temporary
    })
  end

  def get_by_message(message_id) do
    case Horde.Registry.lookup(HordeRegistry, message_id) do
      [{pid, _}] -> GenServer.call(pid, :get_data)
      [] -> nil
    end
  end

  def delete_by_message(message_id) do
    case Horde.Registry.lookup(HordeRegistry, message_id) do
      [{pid, _}] -> GenServer.stop(pid)
      [] -> :ok
    end
  end

  # Server Callbacks

  def start_link(message_id, data) do
    # Register the process in the cluster-wide registry
    GenServer.start_link(__MODULE__, data,
      name: {:via, Horde.Registry, {HordeRegistry, message_id}}
    )
  end

  def init(data) do
    # Automatically kill the process when the spawn expires
    schedule_expiry(data.expires_at)
    {:ok, data}
  end

  def handle_call(:get_data, _from, data) do
    {:reply, data, data}
  end

  def handle_info(:expire, data) do
    {:stop, :normal, data}
  end

  defp schedule_expiry(expires_at) do
    ms_remaining = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)
    Process.send_after(self(), :expire, max(0, ms_remaining))
  end
end
