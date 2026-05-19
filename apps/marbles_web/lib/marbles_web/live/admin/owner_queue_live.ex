defmodule MarblesWeb.Admin.OwnerQueueLive do
  @moduledoc "Owner-only runtime view + admin control over the quick-race queue."

  use MarblesWeb, :live_view

  alias Marbles.Audit
  alias Marbles.Racing.{Engine, Queue}

  @refresh_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Marbles.PubSub, Queue.public_topic())
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    {:ok,
     socket
     |> assign(:page_title, "Queue")
     |> assign(:current_scope, :owner_queue)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Queue", nil}])
     |> assign(:fill_bracket, "")
     |> assign(:fill_count, 4)
     |> assign(:force_bracket, "")
     |> assign(:cancel_race_id, "")
     |> load_state()}
  end

  defp load_state(socket) do
    entries = Queue.admin_list_entries()
    stats = Queue.stats()

    socket
    |> assign(:entries, entries)
    |> assign(:stats, stats)
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load_state(socket)}
  end

  def handle_info({:queue_stats, _stats}, socket), do: {:noreply, load_state(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("kick", %{"id" => user_id}, socket) do
    case Queue.admin_kick(user_id) do
      :ok ->
        Audit.log("queue.kick",
          actor_id: socket.assigns.current_user.id,
          target_type: "user",
          target_id: user_id
        )

        {:noreply, socket |> put_flash(:info, "User kicked and wage refunded.") |> load_state()}

      {:error, :not_queued} ->
        {:noreply, put_flash(socket, :error, "User not in queue.")}
    end
  end

  def handle_event("force_start", %{"bracket" => bracket_str}, socket) do
    case Integer.parse(bracket_str) do
      {bracket, ""} ->
        case Queue.admin_force_start(bracket) do
          :ok ->
            Audit.log("queue.force_start",
              actor_id: socket.assigns.current_user.id,
              metadata: %{bracket: bracket}
            )

            {:noreply,
             socket
             |> put_flash(:info, "Forced match attempt on bracket #{bracket}.")
             |> load_state()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not force start: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid bracket.")}
    end
  end

  def handle_event("fill_bots", %{"bracket" => bracket_str, "count" => count_str}, socket) do
    with {bracket, ""} <- Integer.parse(bracket_str),
         {count, ""} <- Integer.parse(count_str),
         true <- count > 0 do
      {:ok, n} = Queue.admin_fill_bots(bracket, count)

      Audit.log("queue.fill_bots",
        actor_id: socket.assigns.current_user.id,
        metadata: %{bracket: bracket, requested: count, injected: n}
      )

      {:noreply,
       socket |> put_flash(:info, "Injected #{n} bots into bracket #{bracket}.") |> load_state()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid bracket/count.")}
    end
  end

  def handle_event("cancel_race", %{"race_id" => race_id}, socket) do
    if Engine.engine_running?(race_id) do
      Engine.cancel(race_id)

      Audit.log("race.cancel",
        actor_id: socket.assigns.current_user.id,
        target_type: "race",
        target_id: race_id
      )

      {:noreply,
       socket
       |> put_flash(
         :info,
         "Race #{race_id} fast-forwarded to finish. (Refund semantics not yet implemented.)"
       )
       |> load_state()}
    else
      {:noreply, put_flash(socket, :error, "Race not running.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
      show_login_modal={@show_login_modal}
    >
      <section class="space-y-5">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Queue runtime</h1>
          <span class="text-sm text-base-content/60">
            {@stats.total} queued · {map_size(@stats.brackets)} bracket(s)
          </span>
        </header>

        <%!-- Brackets summary --%>
        <div class="grid gap-2 grid-cols-2 md:grid-cols-4 lg:grid-cols-6">
          <div
            :for={{bucket, count} <- Enum.sort(Map.to_list(@stats.brackets))}
            class="rounded-xl border border-base-300 bg-base-200/50 p-3"
          >
            <p class="text-xs text-base-content/60">Bracket {bucket}</p>
            <p class="text-xl font-semibold">{count}</p>
            <p class="text-[10px] text-base-content/50">
              ELO {bucket * @stats.bracket_step}–{(bucket + 1) * @stats.bracket_step}
            </p>
          </div>
          <div
            :if={@stats.brackets == %{}}
            class="col-span-full rounded-xl border border-base-300 bg-base-200/30 p-4 text-center text-sm text-base-content/60"
          >
            Queue empty.
          </div>
        </div>

        <%!-- Admin actions --%>
        <div class="grid gap-3 md:grid-cols-3">
          <.form
            for={%{}}
            phx-submit="force_start"
            id="force-start-form"
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-3 space-y-2"
          >
            <p class="text-xs font-semibold">Force start bracket</p>
            <input
              type="text"
              name="bracket"
              placeholder="bracket #"
              class="input input-bordered input-sm w-full"
            />
            <button type="submit" class="btn btn-warning btn-sm w-full">Force start</button>
          </.form>

          <.form
            for={%{}}
            phx-submit="fill_bots"
            id="fill-bots-form"
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-3 space-y-2"
          >
            <p class="text-xs font-semibold">Fill bots</p>
            <div class="flex gap-1">
              <input
                type="text"
                name="bracket"
                placeholder="bracket #"
                class="input input-bordered input-sm w-full"
              />
              <input
                type="number"
                name="count"
                value="4"
                min="1"
                max="20"
                class="input input-bordered input-sm w-20"
              />
            </div>
            <button type="submit" class="btn btn-secondary btn-sm w-full">Inject</button>
          </.form>

          <.form
            for={%{}}
            phx-submit="cancel_race"
            id="cancel-race-form"
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-3 space-y-2"
          >
            <p class="text-xs font-semibold">Cancel race</p>
            <input
              type="text"
              name="race_id"
              placeholder="race uuid"
              class="input input-bordered input-sm w-full font-mono"
            />
            <button type="submit" class="btn btn-error btn-sm w-full">Cancel</button>
          </.form>
        </div>

        <%!-- Recent starts --%>
        <div
          :if={@stats.recent_starts != []}
          class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-3"
        >
          <p class="text-xs font-semibold mb-2">Recent starts</p>
          <ul class="space-y-1 text-xs font-mono">
            <li :for={s <- @stats.recent_starts}>
              <span class="text-base-content/60">{format_relative(s.at)}</span>
              · <span>{s.count} players</span>
              · <span>{s.race_id}</span>
            </li>
          </ul>
        </div>

        <%!-- Queued entries --%>
        <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>User</th>
                <th>Bracket</th>
                <th>ELO</th>
                <th>Wage</th>
                <th>Wait</th>
                <th>Kind</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={e <- @entries} id={"queue-row-#{e.user_id}"}>
                <td class="font-mono text-xs">{String.slice(e.user_id, 0..7)}</td>
                <td>{e.bracket}</td>
                <td class="text-xs">{e.elo}</td>
                <td class="text-xs">{e.wage}</td>
                <td class="text-xs">{format_wait(e.waited_ms)}</td>
                <td>
                  <span :if={e.bot} class="badge badge-ghost badge-xs">bot</span>
                  <span :if={not e.bot} class="badge badge-primary badge-xs">human</span>
                </td>
                <td class="text-right">
                  <button
                    type="button"
                    phx-click="kick"
                    phx-value-id={e.user_id}
                    data-confirm="Kick this user from the queue? Wage will be refunded."
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Kick
                  </button>
                </td>
              </tr>
              <tr :if={@entries == []}>
                <td colspan="7" class="text-center text-base-content/60 py-6">Queue empty.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_wait(ms) when ms < 1000, do: "<1s"
  defp format_wait(ms) when ms < 60_000, do: "#{div(ms, 1000)}s"
  defp format_wait(ms), do: "#{div(ms, 60_000)}m #{div(rem(ms, 60_000), 1000)}s"

  defp format_relative(unix_seconds) do
    elapsed = System.system_time(:second) - unix_seconds

    cond do
      elapsed < 60 -> "#{elapsed}s ago"
      elapsed < 3600 -> "#{div(elapsed, 60)}m ago"
      true -> "#{div(elapsed, 3600)}h ago"
    end
  end
end
