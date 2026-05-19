defmodule MarblesWeb.Admin.GuildDetailLive do
  use MarblesWeb, :live_view

  alias Marbles.Analytics
  alias MarblesWeb.Admin.GuildChannelForms
  alias Marbles.Guilds
  alias Marbles.Schema.Channel
  alias MarblesWeb.Discord.GuildChannels

  @impl true
  def mount(%{"guild_id" => guild_id}, _session, socket) do
    list_path = guild_list_path(socket)
    {current_scope, route_scope} = scope_pair(socket)

    case Guilds.get_guild(guild_id) do
      nil ->
        {:ok,
         socket
         |> assign(:current_scope, current_scope)
         |> put_flash(:error, "That server was not found.")
         |> push_navigate(to: list_path)}

      guild ->
        {:ok, load_guild_page(socket, guild, route_scope, current_scope)}
    end
  end

  defp scope_pair(socket) do
    case socket.assigns.guild_route_scope do
      :owner -> {:owner_admin, :owner}
      _ -> {:guild_admin, :server}
    end
  end

  defp guild_list_path(socket) do
    case socket.assigns.guild_route_scope do
      :owner -> ~p"/admin/owner/guilds"
      _ -> ~p"/admin"
    end
  end

  defp load_guild_page(socket, guild, route_scope, current_scope) do
    channels = Guilds.list_channels_by_guild(guild.id)
    pulls = Analytics.pulls_today(guild.id)
    spawns = Analytics.spawns_today(guild.id)

    breadcrumbs =
      case route_scope do
        :owner ->
          [
            {"Owner", ~p"/admin/owner"},
            {"Guilds", ~p"/admin/owner/guilds"},
            {guild.name, nil}
          ]

        _ ->
          [{"Servers", ~p"/admin"}, {guild.name, nil}]
      end

    socket
    |> assign(:page_title, guild.name)
    |> assign(:current_scope, current_scope)
    |> assign(:guild, guild)
    |> assign(:channels, channels)
    |> assign(:pulls_today, pulls)
    |> assign(:spawns_today, spawns)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:discord_bot_ready?, GuildChannels.bot_token?())
    |> assign(:discord_channels_loading?, false)
    |> assign(:discord_fetched_channels, nil)
    |> assign(:unused_channel_rows, [])
    |> assign(:channel_rows, GuildChannelForms.rows_saved(channels))
  end

  @impl true
  def handle_event("fetch_discord_channels", _params, socket) do
    guild = socket.assigns.guild

    cond do
      guild.platform != "discord" ->
        {:noreply, put_flash(socket, :error, "Not a Discord server.")}

      not socket.assigns.discord_bot_ready? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Discord bot token is not configured for this web app (set DISCORD_BOT_TOKEN / Nostrum token)."
         )}

      true ->
        socket = assign(socket, :discord_channels_loading?, true)

        case GuildChannels.fetch_previews(guild.id) do
          {:ok, previews} ->
            {:noreply,
             socket
             |> assign(:discord_channels_loading?, false)
             |> assign(:discord_fetched_channels, previews)
             |> assign(
               :unused_channel_rows,
               GuildChannelForms.rows_unused(socket.assigns.channels, previews)
             )
             |> put_flash(:info, "Channels loaded from Discord.")}

          {:error, :missing_bot_token} ->
            {:noreply,
             socket
             |> assign(:discord_channels_loading?, false)
             |> put_flash(:error, "Discord bot token is missing.")}

          {:error, {:http, 401, _}} ->
            {:noreply,
             socket
             |> assign(:discord_channels_loading?, false)
             |> put_flash(:error, "Discord rejected the bot token (401).")}

          {:error, {:http, 403, _}} ->
            {:noreply,
             socket
             |> assign(:discord_channels_loading?, false)
             |> put_flash(
               :error,
               "Discord denied channel list (403). Ensure the bot is in this server and can view channels."
             )}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:discord_channels_loading?, false)
             |> put_flash(:error, "Could not load channels from Discord.")}
        end
    end
  end

  @impl true
  def handle_event(
        "save_spawn_rate",
        %{"spawn" => %{"rate" => rate_str, "channel_id" => channel_id}},
        socket
      ) do
    guild = socket.assigns.guild
    channels = socket.assigns.channels

    with %Channel{} = ch <- Enum.find(channels, &(&1.id == channel_id)),
         true <- ch.guild_id == guild.id,
         {:ok, rate} <- GuildChannelForms.parse_spawn_percent(rate_str),
         {:ok, _} <-
           Guilds.upsert_channel_spawn_rate(
             ch.id,
             guild.id,
             guild.name,
             ch.name,
             rate,
             image_url: guild.image_url
           ) do
      channels = Guilds.list_channels_by_guild(guild.id)

      socket =
        socket
        |> put_flash(:info, "Spawn rate updated for #{ch.name}.")
        |> assign(:channels, channels)
        |> assign(:channel_rows, GuildChannelForms.rows_saved(channels))
        |> refresh_unused_if_cached()

      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown channel.")}

      false ->
        {:noreply, put_flash(socket, :error, "Unknown channel.")}

      {:error, :invalid_rate} ->
        {:noreply, put_flash(socket, :error, "Enter a number between 0 and 100.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save that setting.")}
    end
  end

  @impl true
  def handle_event("save_unused_spawn_rate", %{"unused_spawn" => spawn_params}, socket) do
    guild = socket.assigns.guild
    channel_id = spawn_params["channel_id"]
    name = spawn_params["channel_name"] || "channel"
    rate_str = spawn_params["rate"]

    cond do
      guild.platform != "discord" ->
        {:noreply, put_flash(socket, :error, "Not a Discord server.")}

      not is_binary(channel_id) or channel_id == "" ->
        {:noreply, put_flash(socket, :error, "Missing channel.")}

      true ->
        case GuildChannelForms.parse_spawn_percent(rate_str) do
          {:error, :invalid_rate} ->
            {:noreply, put_flash(socket, :error, "Enter a number between 0 and 100.")}

          {:ok, rate} ->
            case Guilds.upsert_channel_spawn_rate(
                   channel_id,
                   guild.id,
                   guild.name,
                   name,
                   rate,
                   image_url: guild.image_url
                 ) do
              {:ok, _} ->
                channels = Guilds.list_channels_by_guild(guild.id)

                socket =
                  socket
                  |> put_flash(:info, "Saved spawn rate for #{name}.")
                  |> assign(:channels, channels)
                  |> assign(:channel_rows, GuildChannelForms.rows_saved(channels))
                  |> refresh_unused_if_cached()

                {:noreply, socket}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not save that setting.")}
            end
        end
    end
  end

  defp refresh_unused_if_cached(socket) do
    case socket.assigns.discord_fetched_channels do
      nil ->
        socket

      fetched when is_list(fetched) ->
        assign(
          socket,
          :unused_channel_rows,
          GuildChannelForms.rows_unused(socket.assigns.channels, fetched)
        )
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
    >
      <div class="space-y-8">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="flex items-start gap-4">
            <.guild_avatar guild={@guild} class="h-14 w-14 shrink-0 rounded-2xl shadow-md" />
            <div>
              <p class="text-xs font-medium uppercase tracking-wide text-base-content/50">Server</p>
              <h1 class="text-2xl font-semibold tracking-tight">{@guild.name}</h1>
              <p class="mt-1 text-sm text-base-content/60">
                Id <span class="font-mono text-xs text-base-content/80">{@guild.id}</span>
                · {@guild.platform}
              </p>
            </div>
          </div>
        </div>

        <div class="grid gap-4 sm:grid-cols-3">
          <div class="rounded-2xl border border-base-300 bg-base-200/40 p-4 shadow-sm">
            <p class="text-xs font-medium uppercase tracking-wide text-base-content/50">Channels</p>
            <p class="mt-2 text-2xl font-semibold tabular-nums">{length(@channels)}</p>
            <p class="mt-1 text-xs text-base-content/60">In database</p>
          </div>
          <div class="rounded-2xl border border-base-300 bg-base-200/40 p-4 shadow-sm">
            <p class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Pulls today
            </p>
            <p class="mt-2 text-2xl font-semibold tabular-nums">{@pulls_today}</p>
            <p class="mt-1 text-xs text-base-content/60">This server</p>
          </div>
          <div class="rounded-2xl border border-base-300 bg-base-200/40 p-4 shadow-sm">
            <p class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Spawns today
            </p>
            <p class="mt-2 text-2xl font-semibold tabular-nums">{@spawns_today}</p>
            <p class="mt-1 text-xs text-base-content/60">This server</p>
          </div>
        </div>

        <section
          :if={@guild.platform == "discord"}
          class="rounded-2xl border border-base-300 bg-base-200/30 p-4"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-lg font-semibold">Discord</h2>
            <button
              type="button"
              id="guild-fetch-discord-channels"
              phx-click="fetch_discord_channels"
              disabled={@discord_channels_loading? or not @discord_bot_ready?}
              class={[
                "inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold",
                "bg-secondary text-secondary-content shadow-sm",
                "transition hover:brightness-110 active:scale-[0.98]",
                (@discord_channels_loading? or not @discord_bot_ready?) &&
                  "pointer-events-none opacity-60"
              ]}
            >
              <.icon
                :if={@discord_channels_loading?}
                name="hero-arrow-path"
                class="size-4 motion-safe:animate-spin"
              />
              <span :if={!@discord_channels_loading?}>Load channel list from Discord</span>
              <span :if={@discord_channels_loading?}>Loading…</span>
            </button>
          </div>
          <p :if={not @discord_bot_ready?} class="mt-2 text-xs text-base-content/60">
            Needs DISCORD_BOT_TOKEN (same token as the Discord bot).
          </p>
        </section>

        <section class="space-y-3">
          <div>
            <h2 class="text-lg font-semibold">Spawn rates</h2>
            <p class="mt-1 text-sm text-base-content/70">0% turns spawns off.</p>
          </div>

          <div
            :if={@channels == []}
            class="rounded-2xl border border-dashed border-base-300 px-4 py-10 text-center text-sm text-base-content/60"
          >
            No channels in the database yet.
          </div>

          <div :if={@channels != []} class="space-y-4">
            <div
              :for={%{channel: ch, form: f} <- @channel_rows}
              class="rounded-2xl border border-base-300 bg-base-200/30 p-4 shadow-sm transition hover:border-primary/30"
            >
              <.form
                for={f}
                id={"guild-detail-spawn-form-#{ch.id}"}
                phx-submit="save_spawn_rate"
                class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"
              >
                <.input field={f[:channel_id]} type="hidden" />
                <div class="min-w-0 flex-1">
                  <p class="font-medium">{ch.name}</p>
                  <p class="mt-0.5 truncate font-mono text-xs text-base-content/50">{ch.id}</p>
                </div>
                <div class="flex flex-wrap items-end gap-3">
                  <.input field={f[:rate]} type="number" label="Spawn %" step="0.5" min="0" max="100" />
                  <button
                    type="submit"
                    class={[
                      "inline-flex items-center justify-center rounded-xl px-4 py-2 text-sm font-semibold",
                      "bg-primary text-primary-content shadow-sm",
                      "transition hover:brightness-110 active:scale-[0.98]"
                    ]}
                  >
                    Save
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </section>

        <section :if={@unused_channel_rows != []} class="space-y-3">
          <div>
            <h2 class="text-lg font-semibold">Unused channels</h2>
            <p class="mt-1 text-sm text-base-content/70">
              From Discord, not stored yet. Saving adds them.
            </p>
          </div>

          <div class="space-y-4">
            <div
              :for={row <- @unused_channel_rows}
              class="rounded-2xl border border-dashed border-base-300 bg-base-200/20 p-4"
            >
              <.form
                for={row.form}
                id={"guild-unused-spawn-form-#{row.id}"}
                phx-submit="save_unused_spawn_rate"
                class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"
              >
                <.input field={row.form[:channel_id]} type="hidden" />
                <.input field={row.form[:channel_name]} type="hidden" />
                <div class="min-w-0 flex-1">
                  <p class="font-medium">{row.name}</p>
                  <p class="mt-0.5 truncate font-mono text-xs text-base-content/50">{row.id}</p>
                </div>
                <div class="flex flex-wrap items-end gap-3">
                  <.input
                    field={row.form[:rate]}
                    type="number"
                    label="Spawn %"
                    step="0.5"
                    min="0"
                    max="100"
                  />
                  <button
                    type="submit"
                    class={[
                      "inline-flex items-center justify-center rounded-xl px-4 py-2 text-sm font-semibold",
                      "bg-primary text-primary-content shadow-sm",
                      "transition hover:brightness-110 active:scale-[0.98]"
                    ]}
                  >
                    Save
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
