defmodule MarblesWeb.Admin.GuildListLive do
  use MarblesWeb, :live_view

  alias Marbles.Analytics
  alias Marbles.Guilds

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.guild_route_scope

    guilds =
      Guilds.list_guilds_with_channel_count()
      |> Enum.map(fn {g, ch_count} ->
        pulls = Analytics.pulls_today(g.id)
        spawns = Analytics.spawns_today(g.id)
        %{guild: g, channel_count: ch_count, pulls_today: pulls, spawns_today: spawns}
      end)

    {page_title, breadcrumbs, empty_message, current_scope} = list_meta(scope)

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:current_scope, current_scope)
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:empty_message, empty_message)
     |> assign(:guilds, guilds)}
  end

  defp list_meta(:owner) do
    {
      "Guilds",
      [{"Owner", ~p"/admin/owner"}, {"Guilds", nil}],
      "No guilds yet.",
      :owner_guilds
    }
  end

  defp list_meta(_) do
    {
      "Servers",
      [{"Servers", nil}],
      "No servers yet.",
      :guild_admin
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      breadcrumbs={@breadcrumbs}
    >
      <div class="space-y-6">
        <h1 class="text-2xl font-semibold tracking-tight">{@page_title}</h1>

        <.guild_servers_table
          guilds={@guilds}
          route_scope={@guild_route_scope}
          empty_message={@empty_message}
        />
      </div>
    </Layouts.app>
    """
  end
end
