defmodule MarblesWeb.Admin.OwnerUpgradesLive do
  @moduledoc "Owner-only read-only view of marble upgrade definitions and global stats."

  use MarblesWeb, :live_view

  import Ecto.Query

  alias Marbles.Economy.Upgrades
  alias Marbles.Repo
  alias Marbles.Schema.UserUpgrade

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Marble upgrades")
     |> assign(:current_scope, :owner_upgrades)
     |> assign(:show_login_modal, false)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Upgrades", nil}])
     |> assign(:definitions, Upgrades.definitions())
     |> load_stats()}
  end

  defp load_stats(socket) do
    rows =
      from(u in UserUpgrade,
        group_by: [u.upgrade_key, u.level],
        select: {u.upgrade_key, u.level, count(u.id)}
      )
      |> Repo.all()

    stats =
      Enum.reduce(rows, %{}, fn {key, level, count}, acc ->
        Map.update(acc, key, %{level => count}, &Map.put(&1, level, count))
      end)

    assign(socket, :stats_by_key, stats)
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
          <h1 class="text-2xl font-bold">Marble upgrades</h1>
          <span class="text-xs text-base-content/60">
            Definitions are code-defined. Edit `Marbles.Economy.Upgrades` to change.
          </span>
        </header>

        <div class="grid gap-3 md:grid-cols-2">
          <div
            :for={{key, def} <- @definitions}
            id={"upgrade-card-#{key}"}
            class="rounded-2xl border border-base-300 bg-base-100/60 backdrop-blur p-4 space-y-2"
          >
            <div class="flex items-center justify-between">
              <h2 class="font-semibold">{def.title}</h2>
              <span class="font-mono text-xs text-base-content/50">{key}</span>
            </div>
            <p class="text-xs text-base-content/60">Max level: {def.max_level}</p>

            <table class="table table-xs">
              <thead>
                <tr>
                  <th>Level</th>
                  <th>Cost (dust)</th>
                  <th>Users at level</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{cost, idx} <- Enum.with_index(def.costs, 1)}>
                  <td>{idx}</td>
                  <td>{cost}</td>
                  <td>{Map.get(@stats_by_key[key] || %{}, idx, 0)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
