defmodule MarblesWeb.BroadcastLive do
  use MarblesWeb, :live_view
  alias Marbles.Broadcast
  alias Marbles.Guilds

  @impl true
  def mount(_params, _session, socket) do
    guilds_with_channels = Guilds.list_guilds_with_channel_count()

    {:ok,
     socket
     |> assign(:page_title, "Broadcast")
     |> assign(:current_scope, :broadcast)
     |> assign(:wide, true)
     |> assign(:message, "")
     |> assign(:target, "all")
     |> assign(:selected_guild_ids, [])
     |> assign(:guilds, guilds_with_channels)
     |> assign(:sent, false)}
  end

  @impl true
  def handle_event("update_message", params, socket) do
    msg = Map.get(params, "message", socket.assigns.message)
    {:noreply, assign(socket, message: msg || "")}
  end

  @impl true
  def handle_event("update_target", %{"target" => target}, socket) do
    {:noreply, assign(socket, target: target)}
  end

  @impl true
  def handle_event("toggle_guild", %{"id" => id}, socket) do
    ids = socket.assigns.selected_guild_ids

    selected =
      if id in ids do
        List.delete(ids, id)
      else
        [id | ids]
      end

    {:noreply, assign(socket, selected_guild_ids: selected)}
  end

  @impl true
  def handle_event("send", _params, socket) do
    message = String.trim(socket.assigns.message)
    target = socket.assigns.target
    selected = socket.assigns.selected_guild_ids

    guild_ids =
      if target == "all" or message == "" do
        :all
      else
        selected
      end

    if message != "" do
      Broadcast.send_announcement(message, guild_ids)

      {:noreply,
       socket
       |> assign(:message, "")
       |> assign(:sent, true)
       |> put_flash(:info, "Broadcast sent.")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Enter a message.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_scope={@current_scope}
      wide={true}
    >
      <div class="space-y-6">
        <h1 class="text-2xl font-semibold">Broadcast</h1>
        <p class="text-sm text-base-content/70">
          Send an announcement to Discord servers. The bot must be subscribed to receive it.
        </p>

        <div class="rounded-xl border border-base-300 bg-base-200 p-4 sm:p-6 space-y-4">
          <div>
            <label for="broadcast-message" class="label">
              <span class="label-text">Message</span>
            </label>
            <textarea
              id="broadcast-message"
              name="message"
              rows="4"
              class="textarea textarea-bordered w-full"
              placeholder="Your announcement..."
              phx-change="update_message"
            >{@message}</textarea>
          </div>

          <div class="flex flex-col gap-2">
            <span class="label-text">Target</span>
            <div class="flex flex-wrap gap-4">
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  name="target"
                  value="all"
                  checked={@target == "all"}
                  phx-click="update_target"
                  phx-value-target="all"
                />
                <span>All servers</span>
              </label>
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  name="target"
                  value="selected"
                  checked={@target == "selected"}
                  phx-click="update_target"
                  phx-value-target="selected"
                />
                <span>Selected servers</span>
              </label>
            </div>
          </div>

          <div :if={@target == "selected"} class="space-y-2">
            <span class="label-text">Select guilds</span>
            <div class="max-h-40 overflow-y-auto rounded border border-base-300 p-2 space-y-1">
              <%= for {g, _count} <- @guilds do %>
                <label
                  for={"guild-#{g.id}"}
                  class="flex items-center gap-2 cursor-pointer rounded px-2 py-1 hover:bg-base-100"
                >
                  <input
                    type="checkbox"
                    id={"guild-#{g.id}"}
                    phx-click="toggle_guild"
                    phx-value-id={g.id}
                    checked={g.id in @selected_guild_ids}
                  />
                  <span>{g.name}</span>
                </label>
              <% end %>
            </div>
          </div>

          <div class="flex gap-2">
            <button type="button" phx-click="send" class="btn btn-primary">
              Send broadcast
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
