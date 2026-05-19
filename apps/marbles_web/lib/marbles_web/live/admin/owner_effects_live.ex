defmodule MarblesWeb.Admin.OwnerEffectsLive do
  @moduledoc "Owner-only view of all currently active effects across users."

  use MarblesWeb, :live_view

  alias Marbles.Audit
  alias Marbles.Economy.Effects

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Active effects")
     |> assign(:current_scope, :owner_effects)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Effects", nil}])
     |> assign(:page, 1)
     |> load_effects()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 -> n
        _ -> 1
      end

    {:noreply, socket |> assign(:page, page) |> load_effects()}
  end

  defp load_effects(socket) do
    offset = (socket.assigns.page - 1) * @per_page
    {entries, total} = Effects.list_all_active(@per_page, offset)

    socket
    |> assign(:entries, entries)
    |> assign(:total, total)
    |> assign(:per_page, @per_page)
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    case Effects.revoke(id) do
      {:ok, eff} ->
        Audit.log("effect.revoke",
          actor_id: socket.assigns.current_user.id,
          target_type: "user_effect",
          target_id: id,
          before: %{user_id: eff.user_id, effect_key: eff.effect_key, expires_at: eff.expires_at}
        )

        {:noreply, socket |> put_flash(:info, "Effect revoked.") |> load_effects()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not revoke effect.")}
    end
  end

  def handle_event("extend", %{"effect_id" => id, "seconds" => seconds_str}, socket) do
    case Integer.parse(seconds_str) do
      {n, ""} when n > 0 ->
        case Effects.extend(id, n) do
          {:ok, _} ->
            Audit.log("effect.extend",
              actor_id: socket.assigns.current_user.id,
              target_type: "user_effect",
              target_id: id,
              metadata: %{seconds: n}
            )

            {:noreply, socket |> put_flash(:info, "Effect extended by #{n}s.") |> load_effects()}

          _ ->
            {:noreply, put_flash(socket, :error, "Could not extend.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid seconds.")}
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
          <h1 class="text-2xl font-bold">Active effects</h1>
          <span class="text-sm text-base-content/60">{@total} active</span>
        </header>

        <div class="overflow-x-auto rounded-3xl border border-base-300 bg-base-100/60 backdrop-blur">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>User</th>
                <th>Key</th>
                <th>Scope</th>
                <th>Expires</th>
                <th>Meta</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={e <- @entries} id={"effect-row-#{e.id}"}>
                <td class="font-mono text-xs">
                  <.link navigate={~p"/admin/owner/users/#{e.user_id}"} class="hover:underline">
                    {String.slice(e.user_id, 0..7)}
                  </.link>
                </td>
                <td class="font-mono text-xs">{e.effect_key}</td>
                <td class="text-xs">{e.scope}</td>
                <td class="font-mono text-xs">
                  {Calendar.strftime(e.expires_at, "%Y-%m-%d %H:%M")}
                </td>
                <td class="font-mono text-[10px] max-w-xs truncate">{inspect(e.meta)}</td>
                <td class="text-right space-x-1">
                  <.form
                    for={%{}}
                    phx-submit="extend"
                    class="inline-flex items-center gap-1"
                  >
                    <input type="hidden" name="effect_id" value={e.id} />
                    <input
                      type="number"
                      name="seconds"
                      value="3600"
                      class="input input-bordered input-xs w-20"
                    />
                    <button type="submit" class="btn btn-ghost btn-xs">+s</button>
                  </.form>
                  <button
                    type="button"
                    phx-click="revoke"
                    phx-value-id={e.id}
                    data-confirm="Revoke this effect?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Revoke
                  </button>
                </td>
              </tr>
              <tr :if={@entries == []}>
                <td colspan="6" class="text-center text-base-content/60 py-6">
                  No active effects.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex items-center justify-between">
          <span class="text-xs text-base-content/60">
            Page {@page} of {max(1, ceil(@total / @per_page))}
          </span>
          <div class="flex gap-1">
            <.link
              :if={@page > 1}
              patch={~p"/admin/owner/effects?page=#{@page - 1}"}
              class="btn btn-ghost btn-sm"
            >
              Previous
            </.link>
            <.link
              :if={@page < ceil(@total / @per_page)}
              patch={~p"/admin/owner/effects?page=#{@page + 1}"}
              class="btn btn-ghost btn-sm"
            >
              Next
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
