defmodule MarblesWeb.AdminGuildsTable do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: MarblesWeb.Endpoint,
    router: MarblesWeb.Router,
    statics: MarblesWeb.static_paths()

  import MarblesWeb.CoreComponents, only: [guild_avatar: 1, icon: 1]

  attr :guilds, :list, required: true
  attr :route_scope, :atom, required: true, values: [:server, :owner]
  attr :empty_message, :string, default: "No guilds yet."

  def guild_servers_table(assigns) do
    ~H"""
    <div>
      <div class="overflow-x-auto rounded-2xl border border-base-300 bg-base-200/40 shadow-sm">
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 text-left text-xs font-medium uppercase tracking-wide text-base-content/60">
              <th class="px-4 py-3"></th>
              <th class="px-4 py-3">Server</th>
              <th class="px-4 py-3">Platform</th>
              <th class="px-4 py-3 text-right">Channels</th>
              <th class="px-4 py-3 text-right">Pulls today</th>
              <th class="px-4 py-3 text-right">Spawns today</th>
              <th class="px-4 py-3"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr
              :for={
                %{guild: g, channel_count: ch, pulls_today: pulls, spawns_today: spawns} <- @guilds
              }
              class="transition-colors hover:bg-base-200/80"
            >
              <td class="px-4 py-3"><.guild_avatar guild={g} class="h-9 w-9 rounded-full" /></td>
              <td class="px-4 py-3 font-medium">{g.name}</td>
              <td class="px-4 py-3 text-sm text-base-content/70">{g.platform}</td>
              <td class="px-4 py-3 text-right tabular-nums">{ch}</td>
              <td class="px-4 py-3 text-right tabular-nums">{pulls}</td>
              <td class="px-4 py-3 text-right tabular-nums">{spawns}</td>
              <td class="px-4 py-3 text-right">
                <.link
                  navigate={
                    case @route_scope do
                      :owner -> ~p"/admin/owner/guilds/#{g.id}"
                      _ -> ~p"/admin/guilds/#{g.id}"
                    end
                  }
                  class={[
                    "inline-flex items-center gap-1 rounded-lg px-3 py-1.5 text-sm font-medium",
                    "bg-primary text-primary-content shadow-sm",
                    "transition hover:brightness-110 active:scale-[0.98]"
                  ]}
                >
                  Open <.icon name="hero-chevron-right" class="size-4" />
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@guilds == []}
        class="mt-4 rounded-xl border border-dashed border-base-300 px-4 py-8 text-center text-sm text-base-content/60"
      >
        {@empty_message}
      </p>
    </div>
    """
  end
end
