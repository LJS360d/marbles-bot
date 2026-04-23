defmodule MarblesWeb.Admin.OwnerUserDetailLive do
  use MarblesWeb, :live_view
  alias Marbles.Accounts
  alias Marbles.Collection
  alias Marbles.Economy.Admin, as: EconomyAdmin
  alias Marbles.Economy.Upgrades
  alias Marbles.Economy.Mining
  alias Marbles.Economy.Currency
  alias Marbles.Economy.MineRoster

  @collection_preview 15

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [
       {"Owner", ~p"/admin/owner"},
       {"Users", ~p"/admin/owner/users"},
       {"User", nil}
     ])
     |> assign(:wide, true)}
  end

  @impl true
  def handle_event("set_upgrade_level", %{"upgrade" => params}, socket) do
    key = params["key"] || ""
    level = parse_non_neg(params["level"])
    user = socket.assigns.user

    cond do
      not Upgrades.valid_key?(key) ->
        {:noreply, put_flash(socket, :error, "Unknown upgrade key.")}

      is_nil(level) ->
        {:noreply, put_flash(socket, :error, "Upgrade level must be >= 0.")}

      true ->
        case EconomyAdmin.set_user_upgrade_level(user.id, key, level) do
          {:ok, _} ->
            {:noreply, socket |> put_flash(:info, "Updated #{key}.") |> load_user(user.id)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update upgrade level.")}
        end
    end
  end

  @impl true
  def handle_event("grant_effect", %{"effect" => params}, socket) do
    user = socket.assigns.user
    effect_key = String.trim(params["effect_key"] || "")
    hours = parse_non_neg(params["hours"])

    cond do
      effect_key == "" ->
        {:noreply, put_flash(socket, :error, "Effect key is required.")}

      is_nil(hours) or hours <= 0 ->
        {:noreply, put_flash(socket, :error, "Duration hours must be > 0.")}

      true ->
        case EconomyAdmin.grant_user_effect(user.id, effect_key, hours) do
          {:ok, _} ->
            {:noreply, socket |> put_flash(:info, "Effect granted.") |> load_user(user.id)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not grant effect.")}
        end
    end
  end

  @impl true
  def handle_event("delete_effect", %{"id" => id}, socket) do
    :ok = EconomyAdmin.delete_user_effect(id)
    {:noreply, socket |> put_flash(:info, "Effect removed.") |> load_user(socket.assigns.user.id)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, load_user(socket, id)}
  end

  defp load_user(socket, user_id) do
    user = Accounts.get_user!(user_id)
    {items, total} = Collection.list_user_inventory(user.id, per_page: @collection_preview)
    breadcrumbs = [{"Owner", ~p"/admin/owner"}, {"Users", ~p"/admin/owner/users"}, {"User", nil}]
    upgrades = EconomyAdmin.list_user_upgrades(user.id)
    effects = EconomyAdmin.list_user_effects(user.id)
    mine = Mining.compute_coins(user.id, Mining.max_accrual_seconds(user.id))
    {:ok, roster_names} = MineRoster.view(user.id)

    streak =
      case Marbles.Repo.get_by(Marbles.Schema.UserDailyStreak, user_id: user.id) do
        nil -> %{current_streak: 0, longest_streak: 0, last_claimed_at: nil}
        row -> row
      end

    next_daily_eta = seconds_until_next_daily(streak.last_claimed_at)
    upgrade_map = Map.new(upgrades, &{&1.upgrade_key, &1.level})

    socket
    |> assign(:user, user)
    |> assign(:collection, items)
    |> assign(:collection_total, total)
    |> assign(:streak, streak)
    |> assign(:next_daily_eta, next_daily_eta)
    |> assign(:upgrades, upgrades)
    |> assign(:upgrade_map, upgrade_map)
    |> assign(:upgrade_defs, Upgrades.definitions())
    |> assign(:effects, effects)
    |> assign(:mine_preview, mine)
    |> assign(:roster_names, roster_names)
    |> assign(:breadcrumbs, breadcrumbs)
  end

  defp seconds_until_next_daily(nil), do: 0

  defp seconds_until_next_daily(last_claimed_at) do
    next_midnight =
      last_claimed_at
      |> DateTime.to_date()
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    max(0, DateTime.diff(next_midnight, DateTime.utc_now(), :second))
  end

  defp fmt_eta(0), do: "ready now"
  defp fmt_eta(sec) when sec < 3600, do: "#{div(sec, 60)}m"
  defp fmt_eta(sec) when sec < 86_400, do: "#{div(sec, 3600)}h"
  defp fmt_eta(sec), do: "#{div(sec, 86_400)}d"

  defp parse_non_neg(nil), do: nil
  defp parse_non_neg(""), do: nil

  defp parse_non_neg(v) do
    case Integer.parse(v) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.header current_user={@current_user} />
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6">
        <div class="rounded-xl border border-base-300 bg-base-200 p-4">
          <div class="flex items-center justify-between gap-2">
            <div>
              <h1 class="text-xl font-semibold">{Accounts.primary_display_name(@user)}</h1>
              <p :if={@user.display_name} class="text-sm text-base-content/70">
                {@user.display_name}
              </p>
              <p class="mt-2 text-sm">
                Role: {@user.role} · {@user.currency} {Currency.coin_emoji()} {@user.dust || 0} {Currency.dust_emoji()}
              </p>
            </div>
            <.link navigate={~p"/admin/owner/users/#{@user.id}/edit"} class="btn btn-ghost btn-sm">
              Edit
            </.link>
          </div>
          <div :if={(@user.identities || []) != []} class="mt-1">
            <p class="text-xs text-base-content/60">Identities</p>
            <ul class="mt-0.5 list-inside list-disc space-y-0.5 text-xs text-base-content/60">
              <li :for={i <- @user.identities || []}>
                {i.platform}: {i.username}
              </li>
            </ul>
          </div>
        </div>

        <section class="rounded-xl border border-base-300 bg-base-200 p-4">
          <h2 class="text-lg font-semibold">Cooldowns and mining</h2>
          <p class="mt-2 text-sm text-base-content/70">
            Next daily: {fmt_eta(@next_daily_eta)} · Current streak: {@streak.current_streak} · Longest streak: {@streak.longest_streak}
          </p>
          <p class="mt-1 text-sm text-base-content/70">
            Mine roster slots: {(@user.mine_roster["slots"] || []) |> length()} · Full-cap projected payout: {@mine_preview.coins} {Currency.coin_emoji()}
          </p>
          <p class="mt-1 text-xs text-base-content/60">
            <span :if={@roster_names == []}>Roster is empty.</span>
            <span :if={@roster_names != []}>
              Roster: {Enum.join(@roster_names, ", ")}
            </span>
          </p>
        </section>

        <section class="rounded-xl border border-base-300 bg-base-200 p-4">
          <h2 class="text-lg font-semibold">Upgrades</h2>
          <div class="mt-3 space-y-3">
            <%= for {key, cfg} <- @upgrade_defs do %>
              <.form
                for={%{}}
                as={:upgrade}
                id={"set-upgrade-#{key}"}
                phx-submit="set_upgrade_level"
                class="flex flex-wrap items-end gap-3 rounded-lg border border-base-300 bg-base-100 p-3"
              >
                <input type="hidden" name="upgrade[key]" value={key} />
                <div class="min-w-56">
                  <p class="font-medium">{cfg.title}</p>
                  <p class="text-xs text-base-content/70">Key: {key} · Max {cfg.max_level}</p>
                </div>
                <.input
                  name="upgrade[level]"
                  type="number"
                  label="Level"
                  value={Map.get(@upgrade_map, key, 0)}
                  min="0"
                />
                <button type="submit" class="btn btn-primary btn-sm">Set level</button>
              </.form>
            <% end %>
          </div>
        </section>

        <section class="rounded-xl border border-base-300 bg-base-200 p-4">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-lg font-semibold">Effects</h2>
          </div>
          <.form
            for={%{}}
            as={:effect}
            phx-submit="grant_effect"
            id="grant-effect-form"
            class="mt-3 flex flex-wrap items-end gap-3 rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <.input
              name="effect[effect_key]"
              type="text"
              label="Effect key"
              value=""
              placeholder="boost_mine_yield_manual"
            />
            <.input name="effect[hours]" type="number" label="Hours" value="24" min="1" />
            <button type="submit" class="btn btn-primary btn-sm">Grant effect</button>
          </.form>
          <ul class="mt-3 space-y-2">
            <li
              :for={e <- @effects}
              class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div>
                <p class="font-medium">{e.effect_key}</p>
                <p class="text-xs text-base-content/70">
                  Scope: {e.scope} · Expires: {Calendar.strftime(e.expires_at, "%Y-%m-%d %H:%M UTC")}
                </p>
              </div>
              <button
                type="button"
                phx-click="delete_effect"
                phx-value-id={e.id}
                class="btn btn-error btn-xs"
              >
                Remove
              </button>
            </li>
          </ul>
          <p :if={@effects == []} class="mt-2 text-sm text-base-content/60">No effects.</p>
        </section>

        <section class="rounded-xl border border-base-300 bg-base-200 p-3">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Collection
            </h2>
            <span class="text-xs text-base-content/50 tabular-nums">
              {@collection_total} total<span
                :if={@collection_total > length(@collection)}
                class="text-base-content/40"
              >
                · first {length(@collection)} shown
              </span>
            </span>
          </div>
          <div
            :if={@collection != []}
            class="mt-2 max-h-44 overflow-y-auto rounded-lg border border-base-300/70 bg-base-100/60"
          >
            <ul class="divide-y divide-base-300/50">
              <li
                :for={um <- @collection}
                class="flex items-center justify-between gap-2 px-2 py-1.5 text-xs leading-tight"
              >
                <span class="min-w-0 truncate font-medium">{um.marble.name}</span>
                <span class="shrink-0 tabular-nums text-base-content/50">
                  r{um.marble.rarity} · lv{um.level}
                </span>
              </li>
            </ul>
          </div>
          <p :if={@collection == []} class="mt-2 py-2 text-center text-xs text-base-content/60">
            No marbles.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
