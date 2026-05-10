defmodule Marbles.Racing.Events.Scheduler do
  @moduledoc """
  Periodically polls the events table and starts events whose `start_time`
  has passed but which are not yet running. Idempotent: events whose status
  is already running are skipped.

  Runs once a minute.
  """

  use GenServer
  require Logger

  alias Marbles.Repo
  alias Marbles.Racing.Events.Runner
  alias Marbles.Schema.Event
  import Ecto.Query

  @poll_ms 60_000

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    Process.send_after(self(), :poll, @poll_ms)
    {:ok, %{started: MapSet.new()}}
  end

  @impl true
  def handle_info(:poll, state) do
    now = DateTime.utc_now()

    candidates =
      from(e in Event,
        where: e.active == true and e.start_time <= ^now and e.end_time > ^now
      )
      |> Repo.all()

    started =
      Enum.reduce(candidates, state.started, fn event, acc ->
        if MapSet.member?(acc, event.id) do
          acc
        else
          Logger.info("Scheduler launching event #{event.id}")
          Runner.start_event(event)
          MapSet.put(acc, event.id)
        end
      end)

    Process.send_after(self(), :poll, @poll_ms)
    {:noreply, %{state | started: started}}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
