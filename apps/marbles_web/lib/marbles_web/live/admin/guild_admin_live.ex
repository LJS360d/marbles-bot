defmodule MarblesWeb.Admin.GuildAdminLive do
  use MarblesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Guild admin")
     |> assign(:current_scope, :guild_admin)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="rounded-2xl border border-base-300 bg-base-200 p-6">
        <h1 class="text-xl font-semibold">Guild admin</h1>
        <p class="mt-2 text-base-content/80">
          Manage settings for servers where you are an administrator.
        </p>
        <p class="mt-4 text-sm text-base-content/60">
          Placeholder — server list and per-guild settings coming soon.
        </p>
      </div>
    </Layouts.app>
    """
  end
end
