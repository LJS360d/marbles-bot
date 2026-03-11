defmodule MarblesWeb.BroadcastLive do
  use MarblesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Broadcast")
     |> assign(:current_scope, :broadcast)
     |> assign(:message, "")
     |> assign(:target, "all")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="rounded-2xl border border-base-300 bg-base-200 p-6">
        <h1 class="text-xl font-semibold">Broadcast</h1>
        <p class="mt-2 text-base-content/80">Send a message to all servers or selected servers via the bot.</p>
        <p class="mt-4 text-sm text-base-content/60">Placeholder — message form and server/channel selection coming soon.</p>
      </div>
    </Layouts.app>
    """
  end
end
