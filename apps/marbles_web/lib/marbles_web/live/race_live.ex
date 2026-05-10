defmodule MarblesWeb.RaceLive do
  @moduledoc """
  Live race viewer.

  Subscribes to the race PubSub topic and forwards setup + frame packets
  to the JS hook (`RaceRenderer`) which handles the actual visualization.
  Also displays a deterministic textual leaderboard so the LV is useful
  without JS.
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

    {:ok,
     socket
     |> assign(:page_title, "Race")
     |> assign(:current_scope, :race)
     |> assign(:show_login_modal, false)
     |> assign(:race_id, race_id)
     |> assign(:status, status)
     |> assign(:setup, setup)
     |> assign(:leaderboard, [])
     |> assign(:summary, nil)
     |> assign(:replay_payload_b64, encode_replay(setup))}
  end

  @impl true
  def handle_info({:setup, setup}, socket) do
    {:noreply,
     socket
     |> assign(:status, :running)
     |> assign(:setup, encodable_setup(setup))
     |> push_event("race:setup", encodable_setup(setup))}
  end

  def handle_info({:frames, frames}, socket) do
    leaderboard = leaderboard_from_frames(frames, socket.assigns.leaderboard)

    {:noreply,
     socket
     |> assign(:leaderboard, leaderboard)
     |> push_event("race:frames", %{frames: frames |> Enum.map(&encodable_frame/1)})}
  end

  def handle_info({:finished, summary}, socket),
    do: {:noreply, socket |> assign(:status, :finished) |> assign(:summary, summary)}

  def handle_info(_other, socket), do: {:noreply, socket}

  defp leaderboard_from_frames([], current), do: current

  defp leaderboard_from_frames(frames, _current) do
    last = List.last(frames)

    last.marbles
    |> Enum.sort_by(& &1.rank)
    |> Enum.map(fn m ->
      %{
        id: m.id,
        rank: m.rank,
        status: m.status,
        progress: m.z
      }
    end)
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
      current_scope={:race}
      breadcrumbs={[{"Race", nil}]}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-5">
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
          class="aspect-video w-full rounded-3xl border border-base-300 bg-black"
        >
          <canvas class="h-full w-full block" />
        </div>

        <div class="rounded-3xl border border-base-300 bg-base-100/60 p-5 backdrop-blur">
          <h2 class="font-semibold mb-3">Live leaderboard</h2>
          <%= if @leaderboard == [] do %>
            <p class="text-sm text-base-content/60">Waiting for frames…</p>
          <% else %>
            <ol class="space-y-1 text-sm">
              <li :for={entry <- @leaderboard} class="flex items-center justify-between gap-3">
                <span class="font-mono">#{entry.rank}</span>
                <span class="flex-1 truncate">{entry.id}</span>
                <span class="text-base-content/60">
                  {Float.round(entry.progress, 1)} m · {entry.status}
                </span>
              </li>
            </ol>
          <% end %>
        </div>

        <div
          :if={@summary}
          class="rounded-3xl border border-base-300 bg-base-100/60 p-5 backdrop-blur"
        >
          <h2 class="font-semibold mb-3">Final results</h2>
          <ol class="space-y-1 text-sm">
            <li :for={f <- @summary.finishers} class="flex items-center justify-between gap-3">
              <span class="font-mono">#{f.rank}</span>
              <span class="flex-1 truncate">{f.user_id}</span>
              <span class="text-base-content/60">{f.marble_id}</span>
            </li>
          </ol>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
