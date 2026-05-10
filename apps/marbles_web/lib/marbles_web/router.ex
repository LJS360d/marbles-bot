defmodule MarblesWeb.Router do
  use MarblesWeb, :router

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

    live_session :public_pages,
      on_mount: [{MarblesWeb.Live.AuthHooks, :assign_current_user}] do
      live "/", HomeLive, :index
      live "/gacha", GachaLive, :index
      live "/calendar", CalendarLive, :index
      live "/events/:id", EventLive, :show
      live "/race/:id", RaceLive, :show
    end

    live_session :authed_pages,
      on_mount: [{MarblesWeb.Live.AuthHooks, :assign_current_user}] do
      live "/roster", RosterLive, :index
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
    end

    live_session :owner_guilds,
      on_mount: [
        {MarblesWeb.Live.AuthHooks, :require_owner},
        {MarblesWeb.Live.GuildScope, :owner_guilds}
      ] do
      live "/guilds", GuildListLive, :index
      live "/guilds/:guild_id", GuildDetailLive, :show
    end
  end

  scope "/broadcast", MarblesWeb do
    pipe_through [:browser, :auth, :require_owner]

    live_session :broadcast,
      on_mount: [{MarblesWeb.Live.AuthHooks, :require_owner}] do
      live "/", BroadcastLive, :index
    end
  end

  if Application.compile_env(:marbles_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev", MarblesWeb do
      pipe_through [:browser, :auth]

      live_session :dev_sandbox,
        on_mount: [{MarblesWeb.Live.AuthHooks, :assign_current_user}] do
        live "/sandbox", Dev.SandboxLive, :index
      end
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MarblesWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
