defmodule MarblesWeb.Admin.OwnerGuildsLive do
  use MarblesWeb, :live_view
  alias Marbles.Guilds
  alias Marbles.Analytics

  @impl true
  def mount(_params, _session, socket) do
    guilds_with_channels = Guilds.list_guilds_with_channel_count()

    guilds =
      Enum.map(guilds_with_channels, fn {g, ch_count} ->
        pulls = Analytics.pulls_today(g.id)
        spawns = Analytics.spawns_today(g.id)
        %{guild: g, channel_count: ch_count, pulls_today: pulls, spawns_today: spawns}
      end)

    {:ok,
     socket
     |> assign(:page_title, "Guilds")
     |> assign(:current_scope, :owner_admin)
     |> assign(:breadcrumbs, [{"Owner", ~p"/admin/owner"}, {"Guilds", nil}])
     |> assign(:guilds, guilds)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      wide={true}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6">
        <h1 class="text-2xl font-semibold">Guilds</h1>
        <p class="text-sm text-base-content/70">Servers where the bot is present. Read-only.</p>

        <div class="overflow-x-auto rounded-xl border border-base-300">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th></th>
                <th>Name</th>
                <th>Platform</th>
                <th>Channels</th>
                <th>Pulls today</th>
                <th>Spawns today</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={
                %{guild: g, channel_count: ch, pulls_today: pulls, spawns_today: spawns} <- @guilds
              }>
                <td><.guild_avatar guild={g} class="h-8 w-8" /></td>
                <td>{g.name}</td>
                <td>{g.platform}</td>
                <td>{ch}</td>
                <td>{pulls}</td>
                <td>{spawns}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@guilds == []} class="text-sm text-base-content/60">No guilds yet.</p>
      </div>
    </Layouts.app>
    """
  end
end
