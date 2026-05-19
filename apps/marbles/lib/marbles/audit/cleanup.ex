defmodule Marbles.Audit.Cleanup do
  @moduledoc """
  Periodically prunes audit log entries past the retention window.
  Started by `Marbles.Application`.
  """

  use GenServer
  require Logger

  alias Marbles.Audit

  # 1 hour
  @tick_ms 3_600_000

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    schedule_tick()
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    {deleted, _} = Audit.cleanup_expired()
    if deleted > 0, do: Logger.info("Audit.Cleanup: pruned #{deleted} rows")
    schedule_tick()
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)
end
