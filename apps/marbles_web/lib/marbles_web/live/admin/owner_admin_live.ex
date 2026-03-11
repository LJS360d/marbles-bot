defmodule MarblesWeb.Admin.OwnerAdminLive do
  use MarblesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Owner admin")
     |> assign(:current_scope, :owner_admin)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="rounded-2xl border border-base-300 bg-base-200 p-6">
        <h1 class="text-xl font-semibold">Owner admin</h1>
        <p class="mt-2 text-base-content/80">Full system configuration and management.</p>
        <p class="mt-4 text-sm text-base-content/60">Placeholder — global settings and moderation coming soon.</p>
      </div>
    </Layouts.app>
    """
  end
end
