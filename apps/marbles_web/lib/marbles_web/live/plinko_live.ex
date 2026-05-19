defmodule MarblesWeb.PlinkoLive do
  @moduledoc """
  Daily Plinko page. User drops a marble through a 3D Galton board to claim
  their daily reward with a multiplier determined by which slot the marble lands in.
  """

  use MarblesWeb, :live_view

  alias Marbles.Daily
  alias Marbles.Plinko
  alias Marbles.Economy.{Currency, Wallet}
  alias Marbles.IntegerDisplay

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    socket =
      socket
      |> assign(:page_title, "Daily Plinko")
      |> assign(:current_scope, nil)
      |> assign(:state, :ready)
      |> assign(:result, nil)
      |> assign(:slots, Plinko.slots())
      |> assign(:num_rows, Plinko.num_rows())
      |> assign(:num_slots, Plinko.num_slots())
      |> assign_user_data(user)

    {:ok, socket}
  end

  @spec assign_user_data(Phoenix.LiveView.Socket.t(), map() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp assign_user_data(socket, nil) do
    socket
    |> assign(:daily_status, %{claimable: false, seconds_until: 0})
    |> assign(:preview_marble, nil)
    |> assign(:wallet, nil)
  end

  defp assign_user_data(socket, user) do
    preview = Plinko.roll(user.id)

    socket
    |> assign(:daily_status, Daily.claim_status(user.id))
    |> assign(:preview_marble, preview.marble)
    |> assign(:wallet, Wallet.balances(user.id))
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("drop", _params, socket) do
    user = socket.assigns.current_user

    cond do
      user == nil ->
        {:noreply, put_flash(socket, :error, "Sign in to claim.")}

      socket.assigns.state != :ready ->
        {:noreply, socket}

      not socket.assigns.daily_status.claimable ->
        {:noreply, put_flash(socket, :error, "Daily already claimed.")}

      true ->
        case Daily.claim_daily(user.id) do
          {:ok, result} ->
            socket =
              socket
              |> assign(:state, :dropping)
              |> assign(:result, result)
              |> push_event("plinko:drop", %{
                slot: result.plinko_slot.id,
                seed: result.plinko_seed,
                texture_url: marble_texture_url(result.plinko_marble),
                marble_name: marble_name(result.plinko_marble)
              })

            {:noreply, socket}

          {:error, reason} when is_binary(reason) ->
            {:noreply, put_flash(socket, :error, reason)}
        end
    end
  end

  def handle_event("plinko:done", _params, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:state, :done)
      |> assign(:daily_status, Daily.claim_status(user.id))
      |> assign(:wallet, Wallet.balances(user.id))

    {:noreply, socket}
  end

  @spec marble_texture_url(map() | nil) :: String.t() | nil
  defp marble_texture_url(nil), do: nil
  defp marble_texture_url(%{marble: %{texture_path: path}}) when is_binary(path), do: path
  defp marble_texture_url(_), do: nil

  @spec marble_name(map() | nil) :: String.t() | nil
  defp marble_name(nil), do: nil
  defp marble_name(%{marble: %{name: name}}), do: name
  defp marble_name(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} race_state={@race_state} current_scope={nil}>
      <div id="plinko-page" class="relative isolate min-h-svh">
        <div
          aria-hidden="true"
          class="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(80rem_40rem_at_50%_-20%,oklch(72%_0.18_280/0.35),transparent),radial-gradient(60rem_40rem_at_80%_60%,oklch(75%_0.15_30/0.2),transparent)]"
        />

        <section class="mx-auto flex max-w-2xl flex-col items-center gap-6 px-4 py-10">
          <header class="text-center">
            <h1 class="text-3xl font-black tracking-tight">Daily Plinko</h1>
            <p class="mt-1 text-sm text-base-content/60">
              Drop your marble · land center for max reward
            </p>
          </header>

          <%!-- Slot multiplier labels --%>
          <div class="w-full">
            <div class="flex justify-between px-1">
              <%= for slot <- @slots do %>
                <div class="flex flex-col items-center gap-0.5 flex-1">
                  <span class={[
                    "text-xs font-bold font-mono",
                    slot.id == 3 && "text-primary text-sm",
                    slot.id in [2, 4] && "text-secondary",
                    slot.id not in [2, 3, 4] && "text-base-content/50"
                  ]}>
                    {slot.label}
                  </span>
                  <%= if slot.xp_mult > 1.0 do %>
                    <span class="text-[10px] text-success font-mono">+XP</span>
                  <% else %>
                    <span class="text-[10px] opacity-0">·</span>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Three.js Plinko canvas --%>
            <div
              id="plinko-canvas"
              phx-hook="PlinkoScene"
              phx-update="ignore"
              data-num-slots={@num_slots}
              data-num-rows={@num_rows}
              class="w-full rounded-2xl overflow-hidden border border-base-300 bg-[oklch(12%_0.02_280)]"
              style="aspect-ratio: 2/3;"
            />
          </div>

          <%!-- Controls / state --%>
          <%= cond do %>
            <% @current_user == nil -> %>
              <p class="text-sm text-base-content/60">
                <.link navigate={~p"/login"} class="link">Sign in</.link> to play.
              </p>
            <% @state == :done && @result != nil -> %>
              <.result_card result={@result} />
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm rounded-full">
                <.icon name="hero-arrow-left" class="size-4" /> Back home
              </.link>
            <% @state == :dropping -> %>
              <div class="flex items-center gap-2 text-sm text-base-content/60">
                <span class="loading loading-dots loading-sm" /> Dropping…
              </div>
            <% @daily_status.claimable -> %>
              <div class="flex flex-col items-center gap-3">
                <%= if @preview_marble do %>
                  <p class="text-sm text-base-content/60">
                    Dropping: <span class="font-semibold">{@preview_marble.marble.name}</span>
                    <span class="text-base-content/40 ml-1">Lv.{@preview_marble.level}</span>
                  </p>
                <% end %>
                <button
                  type="button"
                  phx-click="drop"
                  id="plinko-drop-btn"
                  class="btn btn-primary rounded-full px-10 text-base btn-chunky"
                >
                  <.icon name="hero-arrow-down-circle" class="size-5" /> Drop!
                </button>
              </div>
            <% true -> %>
              <p class="text-sm text-base-content/60">
                Next drop in
                <span class="font-mono font-semibold">{fmt_eta(@daily_status.seconds_until)}</span>
              </p>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :result, :map, required: true

  defp result_card(assigns) do
    ~H"""
    <div class="rounded-3xl border border-base-300 bg-base-100/70 p-6 backdrop-blur w-full space-y-4 panel-bevel">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-xs uppercase tracking-widest text-base-content/50">Plinko result</p>
          <p class="text-5xl font-black text-primary mt-1">{@result.plinko_slot.label}</p>
        </div>
        <%= if @result.plinko_slot.xp_mult > 1.0 do %>
          <div class="rounded-2xl bg-success/20 border border-success/30 px-4 py-2 text-center">
            <p class="text-xs text-success/70 uppercase tracking-wider">XP boost</p>
            <p class="text-lg font-bold text-success">
              +{round(@result.plinko_slot.xp_mult * 100) - 100}%
            </p>
          </div>
        <% end %>
      </div>

      <div class="divider my-0" />

      <div class="space-y-2 text-sm">
        <div class="flex justify-between items-center">
          <span class="text-base-content/60">Total coins</span>
          <span class="coin-chip text-lg">
            {IntegerDisplay.format(@result.coins)} {Currency.coin_emoji()}
          </span>
        </div>
        <div class="flex justify-between items-center">
          <span class="text-base-content/60">Streak bonus</span>
          <span class="font-mono">
            {IntegerDisplay.format(@result.streak_coins)} · day {@result.streak}
          </span>
        </div>
        <%= if @result.mining_coins > 0 do %>
          <div class="flex justify-between items-center">
            <span class="text-base-content/60">Mining payout</span>
            <span class="font-mono">{IntegerDisplay.format(@result.mining_coins)}</span>
          </div>
        <% end %>
        <%= if (@result.mining_xp_total || 0) > 0 do %>
          <div class="flex justify-between items-center">
            <span class="text-base-content/60">Mining XP</span>
            <span class="font-mono text-success">
              +{IntegerDisplay.format(@result.mining_xp_total)}
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @spec fmt_eta(non_neg_integer()) :: String.t()
  defp fmt_eta(sec) when sec <= 0, do: "now"
  defp fmt_eta(sec) when sec < 3600, do: "#{div(sec, 60)}m"

  defp fmt_eta(sec) do
    h = div(sec, 3600)
    m = div(rem(sec, 3600), 60)
    "#{h}h #{m}m"
  end
end
