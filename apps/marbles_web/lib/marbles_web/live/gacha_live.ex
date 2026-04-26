defmodule MarblesWeb.GachaLive do
  use MarblesWeb, :live_view

  alias Marbles.Assets
  alias Marbles.GachaSession
  alias Marbles.IntegerDisplay
  alias Marbles.Economy.Currency

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Gacha")
      |> assign(:current_scope, :gacha)
      |> assign(:show_login_modal, false)
      |> assign(:selected_pack_id, nil)
      |> assign(:packs_lookup, %{})
      |> assign(:confirm_open, false)
      |> assign(:pending_pull_kind, nil)
      |> assign(:preview, nil)
      |> assign(:skip_confirm, false)
      |> assign(:animation_phase, :idle)
      |> assign(:animation_progress, %{index: 0, total: 0, phase: "idle"})
      |> assign(:latest_result, nil)
      |> assign(:last_pull_kind, nil)
      |> assign(:confirm_form, to_form(%{"skip_confirm" => false}, as: :confirm))
      |> stream_configure(:packs, dom_id: &"pack-#{&1.pack.id}")

    {:ok, refresh_packs(socket)}
  end

  @impl true
  def handle_event("select_pack", %{"pack_id" => pack_id}, socket) do
    {:noreply, assign(socket, :selected_pack_id, pack_id)}
  end

  def handle_event("pull", %{"kind" => kind}, socket) do
    if socket.assigns.current_user == nil do
      {:noreply, assign(socket, :show_login_modal, true)}
    else
      perform_pull_entry(socket, kind)
    end
  end

  def handle_event("cancel_confirm", _params, socket) do
    animation_phase =
      if socket.assigns.latest_result, do: :recap, else: :idle

    {:noreply,
     socket
     |> assign(:confirm_open, false)
     |> assign(:pending_pull_kind, nil)
     |> assign(:preview, nil)
     |> assign(:animation_phase, animation_phase)}
  end

  def handle_event("confirm_pull", _params, socket) do
    case socket.assigns.pending_pull_kind do
      nil ->
        {:noreply, socket}

      pull_kind ->
        execute_pull(socket, pull_kind)
    end
  end

  def handle_event("confirm_pref_changed", %{"confirm" => %{"skip_confirm" => value}}, socket) do
    checked = checkbox_checked?(value)
    {:noreply, assign_skip_confirm(socket, checked)}
  end

  def handle_event("gacha_pref_loaded", %{"skip_confirm" => skip_confirm}, socket) do
    {:noreply, assign_skip_confirm(socket, checkbox_checked?(skip_confirm))}
  end

  def handle_event("gacha_animation_progress", params, socket) do
    phase = Map.get(params, "phase", "running")
    index = Map.get(params, "index", 0)
    total = Map.get(params, "total", 0)

    {:noreply, assign(socket, :animation_progress, %{phase: phase, index: index, total: total})}
  end

  def handle_event("gacha_animation_done", _params, socket) do
    {:noreply, assign(socket, :animation_phase, :recap)}
  end

  def handle_event("skip_animation", _params, socket) do
    {:noreply, push_event(socket, "gacha_animation_skip", %{})}
  end

  def handle_event("pull_again", _params, socket) do
    cond do
      socket.assigns.current_user == nil ->
        {:noreply, assign(socket, :show_login_modal, true)}

      socket.assigns.last_pull_kind == nil ->
        {:noreply, put_flash(socket, :error, "Nothing to repeat.")}

      true ->
        case preview_pull_again(socket) do
          {:ok, preview, pull_kind} ->
            if socket.assigns.skip_confirm do
              execute_pull(socket, pull_kind)
            else
              {:noreply,
               socket
               |> assign(:animation_phase, :idle)
               |> assign(:confirm_open, true)
               |> assign(:preview, preview)
               |> assign(:pending_pull_kind, pull_kind)}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Pull preview failed.")}
        end
    end
  end

  def handle_event("back_to_packs", _params, socket) do
    {:noreply,
     socket
     |> assign(:animation_phase, :idle)
     |> assign(:latest_result, nil)
     |> assign(:last_pull_kind, nil)}
  end

  @impl true
  def render(assigns) do
    selected_pack = selected_pack(assigns)
    quote_one = selected_pack && selected_pack.quote_one
    quote_ten = selected_pack && selected_pack.quote_ten
    pity_line = selected_pack && selected_pack.pity_line
    pity_lines = normalize_pity_lines(pity_line)
    coin = Currency.coin_emoji()
    confirm_preview = assigns.preview

    selected_pack_banner_url =
      selected_pack && Assets.url_for_path(selected_pack.pack.banner_path)

    assigns =
      assigns
      |> assign(:selected_pack, selected_pack)
      |> assign(:quote_one, quote_one)
      |> assign(:quote_ten, quote_ten)
      |> assign(:pity_lines, pity_lines)
      |> assign(:coin, coin)
      |> assign(:confirm_preview, confirm_preview)
      |> assign(:selected_pack_banner_url, selected_pack_banner_url)

    ~H"""
    <Layouts.header current_user={@current_user} />
    <Layouts.app flash={@flash} current_scope={@current_scope} show_login_modal={@show_login_modal}>
      <div id="gacha-page" phx-hook="GachaPage" class="space-y-6">
        <section
          id="gacha-pack-carousel"
          phx-update="stream"
          class="grid gap-4 md:grid-cols-2 xl:grid-cols-3"
        >
          <article
            :for={{dom_id, pack_data} <- @streams.packs}
            id={dom_id}
            class={[
              "group rounded-2xl border bg-base-100 p-5 shadow-sm transition-all",
              @selected_pack_id == pack_data.pack.id &&
                "border-primary shadow-lg shadow-primary/10 ring-1 ring-primary/40",
              @selected_pack_id != pack_data.pack.id && "border-base-300 hover:border-primary/50"
            ]}
          >
            <button
              id={"pack-select-#{pack_data.pack.id}"}
              type="button"
              phx-click="select_pack"
              phx-value-pack_id={pack_data.pack.id}
              class="w-full space-y-3 text-left"
            >
              <div class="flex items-center justify-between">
                <h2 class="text-lg font-medium">{pack_data.pack.name}</h2>
                <span class="rounded-full bg-base-200 px-3 py-1 text-xs text-base-content/70">
                  {IntegerDisplay.format(pack_data.pack.cost || 0)} {@coin}
                </span>
              </div>
              <p class="line-clamp-3 text-sm text-base-content/70">
                {pack_data.pack.description || "No description available."}
              </p>
            </button>
          </article>
        </section>

        <section
          :if={@selected_pack}
          class="rounded-2xl border border-base-300 bg-base-100 p-5 sm:p-6 space-y-5 shadow-sm"
        >
          <div
            :if={@selected_pack_banner_url}
            id="gacha-selected-pack-banner"
            class="overflow-hidden relative rounded-xl border border-base-300 bg-amber-50"
          >
            <img
              src={@selected_pack_banner_url}
              alt={"#{@selected_pack.pack.name} banner"}
              class="h-56 w-full object-cover sm:h-full"
            />
            <ul
              :if={@pity_lines != []}
              class="list-none absolute bottom-4 right-4 space-y-1 text-sm text-primary"
            >
              <li :for={line <- @pity_lines} class="bg-base-300/30 px-3 py-2 rounded-xl">{line}</li>
            </ul>
          </div>

          <div class="grid gap-3 sm:grid-cols-2">
            <button
              id="gacha-pull-one"
              type="button"
              phx-click="pull"
              phx-value-kind="one"
              class="rounded-xl border border-base-300 px-4 py-3 text-sm font-medium transition-colors hover:border-primary hover:bg-primary/10"
            >
              Pull x1
              <span class="text-base-content/70">
                {pull_price_label(@quote_one, @coin)}
              </span>
            </button>

            <button
              id="gacha-pull-ten"
              type="button"
              phx-click="pull"
              phx-value-kind="ten"
              class="rounded-xl bg-primary px-4 py-3 text-sm font-medium text-primary-content transition-all hover:brightness-115"
            >
              Pull x10
              <span class="text-primary-content/80">
                {pull_price_label(@quote_ten, @coin)}
              </span>
            </button>
          </div>
        </section>
      </div>

      <section
        :if={@animation_phase in [:running, :recap]}
        id="gacha-cinematic-overlay"
        class="fixed inset-0 z-60"
      >
        <div
          id="gacha-cinematic"
          phx-hook="GachaCinematic"
          phx-update="ignore"
          class="relative h-full w-full bg-black"
        >
        </div>

        <button
          :if={@animation_phase == :running}
          id="gacha-animation-skip"
          type="button"
          phx-click="skip_animation"
          class="absolute right-5 top-5 rounded-lg border border-white/30 bg-black/40 px-3 py-2 text-xs font-semibold text-white backdrop-blur transition-colors hover:border-white/60 hover:bg-black/60"
        >
          Skip
        </button>

        <div
          :if={@animation_phase == :recap and @latest_result}
          id="gacha-recap-overlay"
          class="absolute inset-0 flex items-center justify-center bg-black/35 p-4 sm:p-6"
        >
          <div class="w-full max-w-5xl max-h-full overflow-y-auto rounded-2xl border border-base-300 bg-base-100 p-5 shadow-2xl sm:p-6 space-y-4">
            <div class="flex items-center justify-between gap-3">
              <h3 class="text-xl font-semibold">Recap</h3>
              <p class="text-sm text-base-content/70">
                Total dust: {IntegerDisplay.format(@latest_result.total_dust)} {Currency.dust_emoji()}
              </p>
            </div>

            <div class="grid gap-5 grid-cols-5">
              <article
                :for={entry <- @latest_result.marbles}
                id={"recap-marble-#{entry.marble.id}"}
                class="rounded-xl border border-base-300 bg-base-50 p-3"
              >
                <div class="flex items-center justify-between">
                  <p class="font-medium">{entry.marble.name}</p>
                  <span class="text-xs text-base-content/70">★{entry.marble.rarity}</span>
                </div>
                <p class="text-xs text-base-content/60">
                  {if entry.duplicate?,
                    do: "Duplicate +#{entry.dust} #{Currency.dust_emoji()}",
                    else: "New"}
                </p>
              </article>
            </div>

            <div class="flex flex-wrap justify-end gap-3">
              <button
                id="gacha-pull-again"
                type="button"
                phx-click="pull_again"
                class="rounded-xl bg-primary px-4 py-2 text-sm font-medium text-primary-content hover:brightness-105"
              >
                Pull again
              </button>
              <button
                id="gacha-back-to-packs"
                type="button"
                phx-click="back_to_packs"
                class="rounded-xl border border-base-300 px-4 py-2 text-sm font-medium hover:border-primary"
              >
                Back to packs
              </button>
            </div>
          </div>
        </div>
      </section>

      <div :if={@confirm_open and @confirm_preview} id="gacha-confirm-modal" class="relative z-50">
        <div class="fixed inset-0 bg-black/50" />
        <div class="fixed inset-0 overflow-y-auto">
          <div class="flex min-h-full items-center justify-center p-4">
            <div class="w-full max-w-lg rounded-2xl border border-base-300 bg-base-100 p-6 shadow-xl space-y-5">
              <div class="space-y-1">
                <h3 class="text-xl font-semibold">Confirm pull</h3>
                <p class="text-sm text-base-content/70">
                  {@confirm_preview.pack.name} — {@confirm_preview.quote.weight} marbles
                </p>
              </div>

              <div class="rounded-xl border border-base-300 bg-base-50 p-4 text-sm">
                <div class="flex items-center justify-between">
                  <span>Wallet before</span>
                  <span id="gacha-wallet-before">
                    {IntegerDisplay.format(@confirm_preview.currency_before)} {@coin}
                  </span>
                </div>
                <div class="flex items-center justify-between">
                  <span>Cost</span>
                  <span id="gacha-wallet-cost">
                    -{IntegerDisplay.format(@confirm_preview.quote.final_price)} {@coin}
                  </span>
                </div>
                <div class="mt-2 border-t border-base-300 pt-2 flex items-center justify-between font-medium">
                  <span>Wallet after</span>
                  <span id="gacha-wallet-after">
                    {IntegerDisplay.format(@confirm_preview.currency_after)} {@coin}
                  </span>
                </div>
              </div>

              <p
                :if={@confirm_preview.currency_before < @confirm_preview.quote.final_price}
                class="rounded-lg bg-warning/20 px-3 py-2 text-sm text-warning"
              >
                Insufficient currency. Top up before pulling.
              </p>

              <.form
                for={@confirm_form}
                id="gacha-confirm-form"
                phx-change="confirm_pref_changed"
                phx-submit="confirm_pull"
                class="space-y-4"
              >
                <.input
                  field={@confirm_form[:skip_confirm]}
                  type="checkbox"
                  label="Don't show this again on this browser"
                  data-gacha-skip-confirm
                />

                <div class="flex justify-end gap-3">
                  <button
                    id="gacha-cancel-confirm"
                    type="button"
                    phx-click="cancel_confirm"
                    class="rounded-lg border border-base-300 px-4 py-2 text-sm font-medium"
                  >
                    Cancel
                  </button>
                  <button
                    id="gacha-confirm-pull"
                    type="submit"
                    class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content"
                  >
                    Confirm pull
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp perform_pull_entry(socket, kind_param) do
    with {:ok, pull_kind} <- parse_pull_kind(kind_param),
         {:ok, pack_id} <- current_pack_id(socket),
         {:ok, preview} <-
           GachaSession.preview_pull_cost(socket.assigns.current_user.id, pack_id, pull_kind) do
      if socket.assigns.skip_confirm do
        execute_pull(socket, pull_kind)
      else
        {:noreply,
         socket
         |> assign(:confirm_open, true)
         |> assign(:preview, preview)
         |> assign(:pending_pull_kind, pull_kind)}
      end
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Pull preview failed.")}
    end
  end

  defp execute_pull(socket, pull_kind) do
    user = socket.assigns.current_user

    case current_pack_id(socket) do
      {:ok, pack_id} ->
        case GachaSession.execute_pull(user.id, pack_id, pull_kind, source: "web_pull") do
          {:ok, result} ->
            socket =
              socket
              |> assign(:confirm_open, false)
              |> assign(:preview, nil)
              |> assign(:pending_pull_kind, nil)
              |> assign(:animation_phase, :running)
              |> assign(:animation_progress, %{
                index: 0,
                total: length(result.marbles),
                phase: "countdown"
              })
              |> assign(:latest_result, result)
              |> assign(:last_pull_kind, result.pull_kind)
              |> refresh_packs()
              |> push_event("gacha_animation_start", animation_payload(result))

            {:noreply, socket}

          {:error, {:insufficient_currency, needed, have}} ->
            {:noreply,
             socket
             |> assign(:confirm_open, false)
             |> put_flash(
               :error,
               "Need #{IntegerDisplay.format(needed)} coins, you have #{IntegerDisplay.format(have)}."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Pull failed. Try again.")}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "No active pack selected.")}
    end
  end

  defp preview_pull_again(socket) do
    pull_kind = socket.assigns.last_pull_kind

    if is_nil(pull_kind) do
      {:error, :no_kind}
    else
      with {:ok, pack_id} <- current_pack_id(socket),
           {:ok, preview} <-
             GachaSession.preview_pull_cost(socket.assigns.current_user.id, pack_id, pull_kind) do
        {:ok, preview, pull_kind}
      end
    end
  end

  defp parse_pull_kind("one"), do: {:ok, :one}
  defp parse_pull_kind("ten"), do: {:ok, :ten}
  defp parse_pull_kind(_), do: {:error, :invalid_pull_kind}

  defp current_pack_id(socket) do
    case socket.assigns.selected_pack_id do
      nil -> {:error, :no_pack_selected}
      id -> {:ok, id}
    end
  end

  defp refresh_packs(socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    packs = GachaSession.list_pullable_packs_for_web(user_id)
    lookup = Map.new(packs, &{&1.pack.id, &1})
    selected_pack_id = keep_selected_pack(socket.assigns.selected_pack_id, packs)

    socket
    |> assign(:packs_lookup, lookup)
    |> assign(:selected_pack_id, selected_pack_id)
    |> stream(:packs, packs, reset: true)
  end

  defp keep_selected_pack(nil, [first | _]), do: first.pack.id
  defp keep_selected_pack(nil, []), do: nil

  defp keep_selected_pack(selected_pack_id, packs) do
    if Enum.any?(packs, &(&1.pack.id == selected_pack_id)) do
      selected_pack_id
    else
      keep_selected_pack(nil, packs)
    end
  end

  defp selected_pack(assigns) do
    Map.get(assigns.packs_lookup, assigns.selected_pack_id)
  end

  defp checkbox_checked?(value) when value in [true, "true", "on", 1, "1"], do: true
  defp checkbox_checked?(_), do: false

  defp assign_skip_confirm(socket, checked) do
    socket
    |> assign(:skip_confirm, checked)
    |> assign(:confirm_form, to_form(%{"skip_confirm" => checked}, as: :confirm))
  end

  defp normalize_pity_lines(nil), do: []
  defp normalize_pity_lines([]), do: []
  defp normalize_pity_lines(lines) when is_list(lines), do: Enum.reject(lines, &(&1 in [nil, ""]))

  defp normalize_pity_lines(line) when is_binary(line) do
    line
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp pull_price_label(%{final_price: 0}, _coin), do: "FREE"

  defp pull_price_label(%{final_price: final_price}, coin),
    do: "(#{IntegerDisplay.format(final_price)} #{coin})"

  defp animation_payload(result) do
    %{
      "pull_kind" => Atom.to_string(result.pull_kind),
      "pack_name" => result.pack.name,
      "results" =>
        Enum.map(result.marbles, fn entry ->
          texture_url = Assets.marble_texture_url(entry.marble)

          %{
            "marble_id" => entry.marble.id,
            "name" => entry.marble.name,
            "rarity" => entry.marble.rarity,
            "duplicate" => entry.duplicate?,
            "dust" => entry.dust,
            "texture_url" => texture_url
          }
        end)
    }
  end
end
