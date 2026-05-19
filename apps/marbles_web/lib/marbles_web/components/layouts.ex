defmodule MarblesWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MarblesWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  @owner_scopes ~w(
    owner_events owner_economy owner_users owner_marbles owner_packs
    owner_teams owner_shop_items owner_guilds owner_admin owner_broadcast
    owner_templates owner_schedules owner_tracks owner_weather owner_abilities
    owner_upgrades owner_queue owner_replays owner_effects owner_analytics
    owner_audit owner_system
  )a

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :any, default: nil
  attr :current_user, :any, default: nil
  attr :race_state, :atom, default: :idle
  attr :breadcrumbs, :list, default: [], doc: "list of {label, path} or {label, nil} for current"
  attr :show_login_modal, :boolean, default: false, doc: "whether to show the login modal"
  slot :inner_block, required: true

  def app(assigns) do
    breadcrumbs = Map.get(assigns, :breadcrumbs, [])
    assigns = assign(assigns, :breadcrumbs, breadcrumbs)
    discord_activity = Application.get_env(:marbles_web, :discord_activity, [])

    discord_activity_url_mappings =
      discord_activity
      |> Keyword.get(:url_mappings, [])
      |> Jason.encode!()

    is_admin = Map.get(assigns, :current_scope, nil) in @owner_scopes

    container_width =
      cond do
        is_admin -> ["p-4", "md:p-6"]
        Map.get(assigns, :current_scope, nil) == nil -> []
        true -> ["p-4", "max-w-screen-2xl"]
      end

    show_bottom_nav = not is_admin

    assigns =
      assigns
      |> assign(:container_width, container_width)
      |> assign(:show_bottom_nav, show_bottom_nav)
      |> assign(:is_admin, is_admin)
      |> assign(:discord_activity_enabled, Keyword.get(discord_activity, :enabled, false))
      |> assign(:discord_activity_client_id, Keyword.get(discord_activity, :client_id))
      |> assign(:discord_activity_redirect_uri, Keyword.get(discord_activity, :redirect_uri))
      |> assign(:discord_activity_url_mappings, discord_activity_url_mappings)

    ~H"""
    <div :if={@is_admin} class="flex min-h-svh">
      <.admin_sidebar current_user={@current_user} current_scope={@current_scope} />
      <div class="flex flex-col flex-1 min-w-0 md:ml-64">
        <div class="sticky top-0 z-40 flex items-center gap-3 border-b border-base-300 bg-base-100/95 backdrop-blur px-4 py-3 md:hidden">
          <label
            for="admin-sidebar-toggle"
            class="flex h-9 w-9 shrink-0 cursor-pointer items-center justify-center rounded-lg hover:bg-base-200 transition-colors"
            aria-label="Open sidebar"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </label>
          <nav
            :if={@breadcrumbs != []}
            class="flex-1 overflow-x-auto text-sm text-base-content/70"
            aria-label="Breadcrumb"
          >
            <ol class="flex flex-nowrap items-center gap-1.5">
              <li>
                <a href={~p"/"} class="hover:text-base-content whitespace-nowrap transition-colors">
                  Home
                </a>
              </li>
              <%= for {label, path} <- @breadcrumbs do %>
                <li class="flex items-center gap-1.5 whitespace-nowrap">
                  <span class="text-base-content/50" aria-hidden="true">/</span>
                  <%= if path do %>
                    <a href={path} class="hover:text-base-content transition-colors">{label}</a>
                  <% else %>
                    <span class="text-base-content font-medium" aria-current="page">{label}</span>
                  <% end %>
                </li>
              <% end %>
            </ol>
          </nav>
        </div>
        <main class="flex-1">
          <div class={["space-y-4", @container_width]}>
            <div
              :if={@discord_activity_enabled}
              id="discord-embedded-auth-bootstrap"
              data-enabled="true"
              data-client-id={@discord_activity_client_id || ""}
              data-auth-endpoint={~p"/api/discord/activity/exchange"}
              data-redirect-uri={@discord_activity_redirect_uri || ""}
              data-url-mappings={@discord_activity_url_mappings}
              class="hidden"
            >
            </div>

            <div class="hidden md:block">
              <.breadcrumbs items={@breadcrumbs} />
            </div>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <div :if={not @is_admin} class="flex min-h-svh">
      <.public_sidebar current_scope={@current_scope} race_state={@race_state} />
      <main class={["flex-1 min-w-0 md:ml-64", @show_bottom_nav && "pb-16 md:pb-0"]}>
        <div class={["space-y-4", @container_width]}>
          <div
            :if={@discord_activity_enabled}
            id="discord-embedded-auth-bootstrap-public"
            data-enabled="true"
            data-client-id={@discord_activity_client_id || ""}
            data-auth-endpoint={~p"/api/discord/activity/exchange"}
            data-redirect-uri={@discord_activity_redirect_uri || ""}
            data-url-mappings={@discord_activity_url_mappings}
            class="hidden"
          >
          </div>

          <.breadcrumbs items={@breadcrumbs} />
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.bottom_tab_bar
      :if={@show_bottom_nav}
      current_scope={@current_scope}
      race_state={Map.get(assigns, :race_state, :idle)}
    />

    <.flash_group flash={@flash} />

    <!-- Login Modal -->
    <div id="login-modal" data-show-modal={@show_login_modal} class="relative z-50 hidden">
      <div
        id="login-modal-backdrop"
        class="fixed inset-0 bg-black/50 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby="login-modal-title"
        role="dialog"
        aria-modal="true"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <div class="relative w-full max-w-md transform overflow-hidden rounded-2xl bg-base-100 p-6 shadow-xl transition-all">
            <div class="absolute right-4 top-4">
              <button
                id="login-modal-close"
                type="button"
                class="rounded-full p-1 hover:bg-base-200"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
            <div class="text-center">
              <h3
                id="login-modal-title"
                class="text-lg font-semibold leading-6 text-base-content mb-2"
              >
                Log in to Marbles
              </h3>
              <p class="text-sm text-base-content/70 mb-6">
                Sign in with your Discord account to start racing and collecting marbles.
              </p>
              <a
                href={~p"/auth/discord"}
                class="inline-flex items-center justify-center gap-2 rounded-xl bg-[#5865F2] px-6 py-3 text-white font-medium hover:opacity-90 hover:scale-105 transition-all focus:ring-2 focus:ring-offset-2 focus:ring-[#5865F2]"
              >
                <svg class="size-5" viewBox="0 0 127.14 96.36" fill="currentColor">
                  <path d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,56.84,124.09,33.37,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z" />
                </svg>
                Log in with Discord
              </a>
              <p class="mt-4 text-xs text-base-content/50">
                By logging in, you agree to our
                <a
                  href={~p"/terms-of-service"}
                  class="underline underline-offset-2 hover:text-base-content/80"
                >
                  Terms of Service
                </a>
                and <a
                  href={~p"/privacy-policy"}
                  class="underline underline-offset-2 hover:text-base-content/80"
                >
                  Privacy Policy
                </a>.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :items, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav :if={@items != []} class="mb-4 text-sm text-base-content/70" aria-label="Breadcrumb">
      <ol class="flex flex-wrap items-center gap-1.5">
        <li><a href={~p"/"} class="hover:text-base-content transition-colors">Home</a></li>
        <%= for {label, path} <- @items do %>
          <li class="flex items-center gap-1.5">
            <span class="text-base-content/50" aria-hidden="true">/</span>
            <%= if path do %>
              <a href={path} class="hover:text-base-content transition-colors">{label}</a>
            <% else %>
              <span class="text-base-content font-medium" aria-current="page">{label}</span>
            <% end %>
          </li>
        <% end %>
      </ol>
    </nav>
    """
  end

  @tab_items [
    {"/", :home, "hero-globe-alt", "Home"},
    {"/squads", :squads, "hero-squares-2x2", "Squads"},
    {"/races", :race, "hero-flag", "Race"},
    {"/gacha", :gacha, "hero-gift", "Gacha"},
    {"/inventory", :inventory, "hero-archive-box", "Inventory"},
    {"/mine", :mine, "hero-cube", "Mines"},
    {"/shop", :shop, "hero-shopping-bag", "Shop"}
  ]

  attr :current_scope, :any, default: nil
  attr :race_state, :atom, default: :idle

  defp bottom_tab_bar(assigns) do
    assigns = assign(assigns, :tab_items, @tab_items)
    assigns = assign(assigns, :current_scope_str, to_string(assigns.current_scope || ""))

    ~H"""
    <nav
      id="bottom-tab-carousel"
      class="fixed bottom-0 left-0 right-0 z-40 border-t border-base-300 bg-base-100/95 backdrop-blur md:hidden"
      phx-hook="BottomTabCarousel"
      data-current-scope={@current_scope_str}
    >
      <div class="relative">
        <button
          type="button"
          data-action="prev"
          class="absolute left-0 top-0 bottom-0 z-10 px-1 flex items-center bg-base-100/95 backdrop-blur"
          aria-label="Previous tabs"
        >
          <.icon name="hero-chevron-left" class="size-4 text-base-content/60" />
        </button>
        <ul
          id="bottom-tab-track"
          data-track
          class="flex items-stretch overflow-x-auto snap-x snap-mandatory scroll-smooth px-6 h-14 scrollbar-none"
        >
          <%= for {path, scope, icon, label} <- @tab_items do %>
            <li class="snap-center flex-none basis-1/5">
              <a
                href={path}
                id={"bottom-tab-#{scope}"}
                data-scope={to_string(scope)}
                class={[
                  "flex h-full flex-col items-center justify-center gap-0.5 mx-0.5 rounded-xl transition-all relative",
                  @current_scope == scope && "text-primary scale-110",
                  @current_scope != scope && "text-base-content/60 hover:text-base-content"
                ]}
              >
                <.icon
                  name={icon}
                  class={["size-5", @current_scope == scope && "drop-shadow"]}
                />
                <span class="text-[10px] font-medium leading-tight">{label}</span>
                <span
                  :if={scope == :race and @race_state in [:queued, :in_race]}
                  class={[
                    "absolute top-1.5 right-1.5 size-2 rounded-full ring-2 ring-base-100",
                    @race_state == :queued && "bg-success animate-pulse",
                    @race_state == :in_race && "bg-error animate-pulse"
                  ]}
                />
              </a>
            </li>
          <% end %>
        </ul>
        <button
          type="button"
          data-action="next"
          class="absolute right-0 top-0 bottom-0 z-10 px-1 flex items-center bg-base-100/95 backdrop-blur"
          aria-label="Next tabs"
        >
          <.icon name="hero-chevron-right" class="size-4 text-base-content/60" />
        </button>
      </div>
    </nav>
    """
  end

  attr :current_scope, :any, default: nil
  attr :race_state, :atom, default: :idle

  defp public_sidebar(assigns) do
    assigns = assign(assigns, :tab_items, @tab_items)

    ~H"""
    <aside class="hidden md:flex flex-col w-64 shrink-0 fixed top-0 left-0 h-svh z-30 border-r border-base-300 bg-base-200">
      <nav class="flex-1 overflow-y-auto p-3 pt-4 space-y-0.5">
        <%= for {path, scope, icon, label} <- @tab_items do %>
          <a
            href={path}
            id={"public-sidebar-#{scope}"}
            class={[
              "flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors relative",
              @current_scope == scope && "bg-primary/15 text-primary font-medium",
              @current_scope != scope &&
                "text-base-content/70 hover:bg-base-300 hover:text-base-content"
            ]}
          >
            <.icon name={icon} class="size-5 shrink-0" />
            <span>{label}</span>
            <span
              :if={scope == :race and @race_state in [:queued, :in_race]}
              class={[
                "ml-auto size-2 rounded-full ring-2 ring-base-200",
                @race_state == :queued && "bg-success animate-pulse",
                @race_state == :in_race && "bg-error animate-pulse"
              ]}
            />
          </a>
        <% end %>
      </nav>
    </aside>
    """
  end

  attr :current_user, :any, default: nil

  def profile_mini_card(assigns) do
    ~H"""
    <a
      :if={@current_user}
      href={~p"/profile"}
      id="profile-mini-card"
      class="inline-flex items-center gap-2 rounded-full bg-base-100/95 backdrop-blur border border-base-300 px-2 py-1.5 shadow hover:shadow-md transition-shadow"
    >
      <div class="size-7 rounded-full bg-base-300 flex items-center justify-center text-xs font-semibold">
        {String.first(Marbles.Accounts.primary_display_name(@current_user) || "?")}
      </div>
      <span class="text-xs font-medium pr-1 max-w-[8rem] truncate">
        {Marbles.Accounts.primary_display_name(@current_user)}
      </span>
    </a>
    <a
      :if={!@current_user}
      href={~p"/login"}
      id="profile-mini-card-login"
      class="inline-flex rounded-full bg-base-100/95 backdrop-blur border border-base-300 px-3 py-1.5 text-xs font-medium shadow hover:shadow-md transition-shadow"
    >
      Log in
    </a>
    """
  end

  defp owner?(nil), do: false
  defp owner?(user), do: user.role == :owner

  defp admin_or_owner?(nil), do: false
  defp admin_or_owner?(user), do: user.role == :server_admin || owner?(user)

  @sidebar_groups [
    {"Overview",
     [
       {"/admin/owner", :owner_admin, "hero-squares-2x2", "Dashboard"}
     ]},
    {"Users & Guilds",
     [
       {"/admin/owner/users", :owner_users, "hero-users", "Users"},
       {"/admin/owner/guilds", :owner_guilds, "hero-globe-alt", "Guilds"}
     ]},
    {"Catalog",
     [
       {"/admin/owner/marbles", :owner_marbles, "hero-sparkles", "Marbles"},
       {"/admin/owner/packs", :owner_packs, "hero-gift", "Packs"},
       {"/admin/owner/teams", :owner_teams, "hero-flag", "Teams"},
       {"/admin/owner/shop-items", :owner_shop_items, "hero-shopping-bag", "Shop items"},
       {"/admin/owner/upgrades", :owner_upgrades, "hero-arrow-trending-up", "Upgrades"},
       {"/admin/owner/abilities", :owner_abilities, "hero-bolt", "Abilities"}
     ]},
    {"Racing",
     [
       {"/admin/owner/templates", :owner_templates, "hero-document-duplicate", "Templates"},
       {"/admin/owner/schedules", :owner_schedules, "hero-clock", "Schedules"},
       {"/admin/owner/events", :owner_events, "hero-calendar-days", "Events"},
       {"/admin/owner/tracks", :owner_tracks, "hero-map", "Tracks"},
       {"/admin/owner/weather", :owner_weather, "hero-cloud", "Weather"},
       {"/admin/owner/queue", :owner_queue, "hero-queue-list", "Queue"},
       {"/admin/owner/replays", :owner_replays, "hero-film", "Replays"}
     ]},
    {"Economy",
     [
       {"/admin/owner/economy", :owner_economy, "hero-banknotes", "Economy"},
       {"/admin/owner/effects", :owner_effects, "hero-sparkles", "Effects"}
     ]},
    {"Ops",
     [
       {"/admin/owner/broadcast", :owner_broadcast, "hero-megaphone", "Broadcast"},
       {"/admin/owner/analytics", :owner_analytics, "hero-chart-bar", "Analytics"},
       {"/admin/owner/audit-log", :owner_audit, "hero-document-text", "Audit log"},
       {"/admin/owner/system", :owner_system, "hero-cpu-chip", "System"}
     ]}
  ]

  attr :current_user, :any, default: nil
  attr :current_scope, :any, default: nil

  def admin_sidebar(assigns) do
    assigns = assign(assigns, :groups, @sidebar_groups)

    ~H"""
    <input type="checkbox" id="admin-sidebar-toggle" class="peer sr-only" />

    <div
      class="fixed inset-0 z-30 bg-black/50 opacity-0 pointer-events-none peer-checked:opacity-100 peer-checked:pointer-events-auto transition-opacity md:hidden"
      aria-hidden="true"
    >
      <label for="admin-sidebar-toggle" class="absolute inset-0" />
    </div>

    <aside class="fixed top-0 left-0 z-40 h-svh w-64 -translate-x-full peer-checked:translate-x-0 md:translate-x-0 transition-transform duration-200 ease-out bg-base-200 border-r border-base-300 flex flex-col">
      <div class="flex items-center justify-between p-4 border-b border-base-300">
        <a href={~p"/admin/owner"} class="flex items-center gap-2">
          <.icon name="hero-shield-check" class="size-5 text-primary" />
          <span class="font-semibold">Owner</span>
        </a>
        <label
          for="admin-sidebar-toggle"
          class="flex h-8 w-8 cursor-pointer items-center justify-center rounded-full hover:bg-base-300 md:hidden"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </label>
      </div>

      <nav class="flex-1 overflow-y-auto p-2 space-y-3">
        <%= for {group_label, items} <- @groups do %>
          <details class="group" open>
            <summary class="cursor-pointer list-none px-3 py-1 text-xs font-semibold uppercase tracking-wide text-base-content/50 hover:text-base-content/80 flex items-center justify-between">
              <span>{group_label}</span>
              <.icon
                name="hero-chevron-down"
                class="size-3 transition-transform group-open:rotate-180"
              />
            </summary>
            <ul class="mt-1 space-y-0.5">
              <%= for {path, scope, icon, label} <- items do %>
                <li>
                  <a
                    href={path}
                    id={"sidebar-#{scope}"}
                    class={[
                      "flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm transition-colors",
                      @current_scope == scope && "bg-primary/15 text-primary font-medium",
                      @current_scope != scope &&
                        "text-base-content/70 hover:bg-base-300 hover:text-base-content"
                    ]}
                  >
                    <.icon name={icon} class="size-4 shrink-0" />
                    <span>{label}</span>
                  </a>
                </li>
              <% end %>
            </ul>
          </details>
        <% end %>
      </nav>

      <div class="border-t border-base-300 p-3 space-y-2">
        <div :if={@current_user} class="flex items-center gap-2 px-2">
          <div class="size-7 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
            {String.first(Marbles.Accounts.primary_display_name(@current_user) || "?")}
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-medium truncate">
              {Marbles.Accounts.primary_display_name(@current_user)}
            </div>
            <div class="text-[10px] text-base-content/50">Owner</div>
          </div>
        </div>
        <div class="flex items-center justify-between gap-2">
          <.theme_toggle />
          <form action={~p"/logout"} method="post" class="shrink-0">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="_method" value="delete" />
            <button
              type="submit"
              class="btn btn-ghost btn-xs"
              aria-label="Logout"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
            </button>
          </form>
        </div>
        <a
          href={~p"/"}
          class="block text-center text-xs text-base-content/60 hover:text-base-content transition-colors"
        >
          ← Back to game
        </a>
      </div>
    </aside>
    """
  end

  attr :current_user, :any, default: nil

  def header(assigns) do
    ~H"""
    <header class="sticky top-0 z-40 flex items-center justify-between gap-4 border-b border-base-300 bg-base-100/95 backdrop-blur px-4 py-3 sm:px-6 lg:px-8 md:mb-4">
      <a
        href={~p"/"}
        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-base-200 transition-colors"
        aria-label="Home"
      >
        <.icon name="hero-home" class="size-6 text-base-content/80" />
      </a>
      <div class="flex items-center gap-2">
        <.theme_toggle />
        <input type="checkbox" id="nav-drawer" class="peer sr-only" />
        <label
          for="nav-drawer"
          class="flex h-10 w-10 cursor-pointer items-center justify-center rounded-full hover:bg-base-200 transition-colors md:hidden"
          aria-label="Menu"
        >
          <.icon name="hero-bars-3" class="size-6" />
        </label>
        <div
          class="fixed inset-0 z-40 bg-black/50 opacity-0 pointer-events-none peer-checked:opacity-100 peer-checked:pointer-events-auto transition-opacity md:hidden"
          aria-hidden="true"
        >
          <label for="nav-drawer" class="absolute inset-0" />
        </div>
        <nav class="fixed top-0 right-0 z-50 h-full w-72 max-w-[85vw] bg-base-100 border-l border-base-300 shadow-xl translate-x-full peer-checked:translate-x-0 transition-transform duration-200 ease-out md:relative md:translate-x-0 md:w-auto md:border-0 md:shadow-none md:bg-transparent">
          <div class="flex items-center justify-between p-4 border-b border-base-300 md:hidden">
            <span class="font-medium">Menu</span>
            <label
              for="nav-drawer"
              class="flex h-10 w-10 cursor-pointer items-center justify-center rounded-full hover:bg-base-200"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </label>
          </div>
          <ul class="flex flex-col gap-1 p-4 md:flex-row md:items-center md:gap-3 md:p-0">
            <li>
              <a
                href={~p"/gacha"}
                class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
              >
                Gacha
              </a>
            </li>
            <%= if @current_user do %>
              <li class="md:hidden">
                <span class="block px-3 py-2 text-sm text-base-content/70">
                  {Marbles.Accounts.primary_display_name(@current_user)}
                </span>
              </li>
              <%= if admin_or_owner?(@current_user) do %>
                <li>
                  <a
                    href={~p"/admin"}
                    class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
                  >
                    Admin
                  </a>
                </li>
              <% end %>
              <%= if owner?(@current_user) do %>
                <li>
                  <a
                    href={~p"/admin/owner"}
                    class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
                  >
                    Owner
                  </a>
                </li>
              <% end %>
              <li>
                <form action={~p"/logout"} method="post" class="block md:inline">
                  <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
                  <input type="hidden" name="_method" value="delete" />
                  <button
                    type="submit"
                    class="w-full text-left rounded-lg px-3 py-2 hover:bg-base-200 md:w-auto md:px-2 md:py-1 md:text-sm"
                  >
                    Logout
                  </button>
                </form>
              </li>
            <% else %>
              <li>
                <a
                  href={~p"/login"}
                  class="block rounded-lg px-3 py-2 hover:bg-base-200 md:inline-block md:px-2 md:py-1 md:text-sm"
                >
                  Login
                </a>
              </li>
            <% end %>
          </ul>
        </nav>
      </div>
    </header>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="toast toast-bottom toast-end z-50" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border border-base-200 bg-base-100 brightness-200 left-0 in-data-[theme=light]:left-1/3 in-data-[theme=dark]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
