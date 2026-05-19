defmodule MarblesWeb.Router do
  use MarblesWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MarblesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth do
    plug MarblesWeb.Plugs.Auth
  end

  pipeline :activity_embed do
    plug MarblesWeb.Plugs.ActivityEmbedHeaders
  end

  pipeline :require_user do
    plug MarblesWeb.Plugs.Auth, :require_user
  end

  pipeline :require_owner do
    plug MarblesWeb.Plugs.Auth, :require_owner
  end

  pipeline :require_server_admin_or_owner do
    plug MarblesWeb.Plugs.Auth, :require_server_admin_or_owner
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  scope "/api/owner", MarblesWeb.Api.Owner do
    pipe_through [:api, :auth, :require_owner]

    get "/stats", StatsController, :index
    post "/broadcast", BroadcastController, :create
  end

  scope "/", MarblesWeb do
    pipe_through [:browser, :auth, :activity_embed]

    get "/privacy-policy", PageController, :privacy_policy
    get "/terms-of-service", PageController, :terms_of_service
    get "/login", AuthController, :login_page
    get "/auth/:provider", AuthController, :request
    get "/auth/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout

    live_session :app_pages,
      on_mount: [{MarblesWeb.Live.AuthHooks, :assign_current_user}] do
      live "/", HomeLive, :index
      live "/daily", PlinkoLive, :index
      live "/plinko", PlinkoLive, :index
      live "/gacha", GachaLive, :index
      live "/calendar", CalendarLive, :index
      live "/events/:id", EventLive, :show
      live "/race/:id", RaceLive, :show

      live "/races", RacesLive, :index
      live "/races/calendar", CalendarLive, :index
      live "/races/race/:id", RaceLive, :show
      live "/races/event/:id", EventLive, :show

      live "/mine", MiningLive, :index
      live "/shop", ShopLive, :index

      live "/squads", SquadsLive, :index
      live "/inventory", InventoryLive, :index
      live "/upgrade-marble", UpgradeMarbleLive, :index
      live "/profile", ProfileLive, :index
      live "/profile/upgrade", UpgradeMarbleLive, :index
    end
  end

  scope "/api/discord/activity", MarblesWeb.Discord do
    pipe_through [:api, :auth]

    post "/exchange", ActivityAuthController, :exchange
  end

  scope "/admin", MarblesWeb.Admin do
    pipe_through [:browser, :auth, :require_user, :require_server_admin_or_owner]

    live_session :guild_admin,
      on_mount: [
        {MarblesWeb.Live.AuthHooks, :assign_current_user},
        {MarblesWeb.Live.GuildScope, :server_guilds}
      ] do
      live "/", GuildListLive, :index
      live "/guilds/:guild_id", GuildDetailLive, :show
    end
  end

  scope "/admin/owner", MarblesWeb.Admin do
    pipe_through [:browser, :auth, :require_owner]

    live_session :owner_admin,
      on_mount: [{MarblesWeb.Live.AuthHooks, :require_owner}] do
      live "/", OwnerAdminLive, :index
      live "/users", OwnerUsersLive, :index
      live "/users/:id", OwnerUserDetailLive, :show
      live "/users/:id/edit", OwnerUserEditLive, :edit
      live "/marbles", OwnerMarblesLive, :index
      live "/marbles/:id/edit", OwnerMarbleEditLive, :edit
      live "/packs", OwnerPacksLive, :index
      live "/packs/new", OwnerPackBuilderLive, :new
      live "/packs/:id/edit", OwnerPackBuilderLive, :edit
      live "/teams", OwnerTeamsLive, :index
      live "/teams/:id/edit", OwnerTeamEditLive, :edit
      live "/economy", OwnerEconomyLive, :index
      live "/shop-items", OwnerShopItemsLive, :index
      live "/events", OwnerEventsLive, :index
      live "/events/new", OwnerEventEditLive, :new
      live "/events/:id/edit", OwnerEventEditLive, :edit
      live "/templates", OwnerEventTemplatesLive, :index
      live "/templates/new", OwnerEventTemplateEditLive, :new
      live "/templates/:id/edit", OwnerEventTemplateEditLive, :edit
      live "/schedules", OwnerSchedulesLive, :index
      live "/schedules/new", OwnerScheduleEditLive, :new
      live "/schedules/:id/edit", OwnerScheduleEditLive, :edit
      live "/tracks", OwnerTracksLive, :index
      live "/tracks/new", OwnerTrackEditLive, :new
      live "/tracks/:id/edit", OwnerTrackEditLive, :edit
      live "/weather", OwnerWeatherLive, :index
      live "/abilities", OwnerAbilitiesLive, :index
      live "/upgrades", OwnerUpgradesLive, :index
      live "/queue", OwnerQueueLive, :index
      live "/replays", OwnerReplaysLive, :index
      live "/effects", OwnerEffectsLive, :index
      live "/analytics", OwnerAnalyticsLive, :index
      live "/audit-log", OwnerAuditLive, :index
      live "/broadcast", BroadcastLive, :index
    end

    live_session :owner_guilds,
      on_mount: [
        {MarblesWeb.Live.AuthHooks, :require_owner},
        {MarblesWeb.Live.GuildScope, :owner_guilds}
      ] do
      live "/guilds", GuildListLive, :index
      live "/guilds/:guild_id", GuildDetailLive, :show
    end

    live_dashboard "/system", metrics: MarblesWeb.Telemetry
  end

  if Application.compile_env(:marbles_web, :dev_routes) do
    scope "/dev", MarblesWeb do
      pipe_through [:browser, :auth]

      live_session :dev_sandbox,
        on_mount: [{MarblesWeb.Live.AuthHooks, :assign_current_user}] do
        live "/sandbox", Dev.SandboxLive, :index
      end
    end
  end
end
