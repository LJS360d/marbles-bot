defmodule MarblesWeb.RaceLive do
  @moduledoc """
  Live race viewer.

  Subscribes to the race PubSub topic and forwards setup + frame packets
  to the JS hook (`RaceRenderer`). Shows the player's own marble position
  during the race, and a full leaderboard overlay when the race ends.
  """

  use MarblesWeb, :live_view

  alias Marbles.Racing.{Engine, Replay}
  alias Phoenix.PubSub

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(Marbles.PubSub, Engine.topic(race_id))

    {setup, status} =
      cond do
        Engine.engine_running?(race_id) ->
          {nil, :running}

        true ->
          case Replay.load(race_id) do
            {:ok, payload} -> {payload, :finished}
            {:error, _} -> {nil, :pending}
          end
      end

    current_user_id = socket.assigns[:current_user] && socket.assigns.current_user.id

    {:ok,
     socket
     |> assign(:page_title, "Race")
     |> assign(:current_scope, :race)
     |> assign(:show_login_modal, false)
     |> assign(:race_id, race_id)
     |> assign(:status, status)
     |> assign(:setup, setup)
     |> assign(:current_user_id, current_user_id)
     |> assign(:my_marble_rank, nil)
     |> assign(:total_marbles, 0)
     |> assign(:summary, nil)
     |> assign(:replay_payload_b64, encode_replay(setup))}
  end

  @impl true
  def handle_info({:setup, setup}, socket) do
    encodable = encodable_setup(setup)
    total = count_marbles(setup)

    {:noreply,
     socket
     |> assign(:status, :running)
     |> assign(:setup, encodable)
     |> assign(:total_marbles, total)
     |> push_event(
       "race:setup",
       Map.put(encodable, :current_user_id, socket.assigns.current_user_id)
     )}
  end

  def handle_info({:frames, frames, ability_triggers}, socket) do
    my_rank = my_marble_rank(frames, socket.assigns.current_user_id)

    socket =
      socket
      |> assign(:my_marble_rank, my_rank)
      |> push_event("race:frames", %{frames: Enum.map(frames, &encodable_frame/1)})

    socket =
      if ability_triggers != [] do
        push_event(socket, "race:abilities", %{triggers: ability_triggers})
      else
        socket
      end

    {:noreply, socket}
  end

  # Backward compat for any old-format broadcasts during dev
  def handle_info({:frames, frames}, socket) do
    handle_info({:frames, frames, []}, socket)
  end

  def handle_info({:finished, summary}, socket),
    do: {:noreply, socket |> assign(:status, :finished) |> assign(:summary, summary)}

  def handle_info(_other, socket), do: {:noreply, socket}

  defp my_marble_rank([], _user_id), do: nil
  defp my_marble_rank(_frames, nil), do: nil

  defp my_marble_rank(frames, user_id) do
    last = List.last(frames)

    Enum.find(last.marbles, fn m -> m.user_id == user_id end)
    |> case do
      nil -> nil
      m -> m.rank
    end
  end

  defp count_marbles(nil), do: 0

  defp count_marbles(setup) do
    Enum.reduce(setup.participants, 0, fn p, acc -> acc + length(p.racers) end)
  end

  defp encodable_setup(nil), do: nil

  defp encodable_setup(setup) do
    setup
    |> Map.update!(:weather, fn w ->
      %{
        key: Atom.to_string(w.key),
        name: w.name,
        modifiers: w.modifiers
      }
    end)
  end

  defp encodable_frame(%{t: t, marbles: marbles}) do
    %{
      t: t,
      marbles:
        Enum.map(marbles, fn m ->
          %{
            id: m.id,
            user_id: m.user_id,
            x: m.x,
            y: m.y,
            z: m.z,
            vel: m.vel,
            rank: m.rank,
            status: Atom.to_string(m.status)
          }
        end)
    }
  end

  defp encode_replay(nil), do: nil

  defp encode_replay(payload) when is_map(payload),
    do: payload |> Jason.encode!() |> Base.encode64()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      race_state={@race_state}
      current_scope={:race}
      breadcrumbs={[{"Race", nil}]}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-4">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Race · {String.slice(@race_id, 0, 8)}</h1>
          <span class={[
            "badge",
            @status == :running && "badge-success",
            @status == :finished && "badge-neutral",
            @status == :pending && "badge-warning"
          ]}>
            {@status}
          </span>
        </header>

        <div
          id="race-renderer"
          phx-hook="RaceRenderer"
          phx-update="ignore"
          data-race-id={@race_id}
          data-replay-b64={@replay_payload_b64 || ""}
          data-current-user-id={@current_user_id || ""}
          class="relative aspect-video w-full rounded-3xl border border-base-300 bg-black overflow-hidden"
        >
          <canvas class="h-full w-full block" />
        </div>

        <%!-- Player's own marble position (replaces per-marble leaderboard) --%>
        <div
          :if={@status == :running and @my_marble_rank != nil}
          class="rounded-3xl border border-base-300 bg-base-100/60 p-4 backdrop-blur flex items-center justify-between panel-bevel"
        >
          <span class="text-sm text-base-content/60">Your position</span>
          <span class="text-2xl font-bold tabular-nums">
            P{@my_marble_rank}
            <span class="text-base font-normal text-base-content/60">/ {@total_marbles}</span>
          </span>
        </div>

        <div
          :if={@status == :running and @my_marble_rank == nil}
          class="text-sm text-base-content/60 text-center py-2"
        >
          Waiting for race to start…
        </div>

        <%!-- End-of-race leaderboard overlay --%>
        <div
          :if={@summary}
          class="rounded-3xl border border-base-300 bg-base-100/60 p-5 backdrop-blur panel-bevel"
        >
          <h2 class="font-semibold mb-4">Race results</h2>
          <ol class="space-y-2">
            <li
              :for={f <- @summary.finishers}
              class={[
                "flex items-center justify-between gap-3 rounded-2xl px-3 py-2 text-sm",
                f.user_id == @current_user_id && "bg-primary/10 border border-primary/30"
              ]}
            >
              <span class="font-mono text-base-content/60 w-6">{f.rank}</span>
              <span class="flex-1 truncate">{f.user_id}</span>
              <span :if={f.user_id == @current_user_id} class="badge badge-primary badge-xs">
                You
              </span>
            </li>
          </ol>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
