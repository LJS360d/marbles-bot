# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :marbles,
  ecto_repos: [Marbles.Repo],
  analytics_adapter: Marbles.Analytics.SQLAdapter,
  pull_item_rewards: [
    %{
      trigger: %{kind: "duplicate_rarity_at_least", min_rarity: 3},
      pull_kinds: ["one", "ten"],
      rewards: [
        %{item_type: "material", item_id: "marble_core", quantity: 1}
      ]
    }
  ],
  item_metadata: %{
    "currency" => %{
      "coins" => %{
        description: "Currency used to pull from gacha packs and other transactions",
        actions: [
          %{type: :get, label: "Racing", link: "/race"},
          %{type: :spend, label: "Gacha", link: "/gacha"},
          %{type: :spend, label: "Shop", link: "/shop"}
        ]
      },
      "dust" => %{
        description: "Crafting material obtained from duplicate marbles",
        actions: [
          %{type: :get, label: "Duplicate Marbles", link: "/roster"},
          %{type: :spend, label: "Crafting", link: "/craft"},
          %{type: :spend, label: "Shop", link: "/shop"}
        ]
      }
    },
    "material" => %{
      "marble_core" => %{
        description: "Used to upgrade 3-star marbles and increase their power level",
        actions: [
          %{type: :get, label: "Duplicate 3-Star Pull", link: "/gacha"},
          %{type: :use, label: "Upgrade Marble", link: "/upgrade-marble"}
        ]
      }
    }
  }

config :marbles, Marbles.Inventory, starter_coins: 1000

# Bracket index = div(elo, queue bracket_step). Default ELO 1000 → bucket 10, so
# low_elo_max_bucket must be >= 10 or starters never receive queue bots.
config :marbles, Marbles.Racing.Queue.BotFill,
  enabled: true,
  interval_ms: 120_000,
  low_elo_max_bucket: 20,
  target_party: 4

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :marbles, Marbles.Mailer, adapter: Swoosh.Adapters.Local

config :marbles_web,
  ecto_repos: [Marbles.Repo],
  generators: [context_app: :marbles]

# Configures the endpoint
config :marbles_web, MarblesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MarblesWeb.ErrorHTML, json: MarblesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Marbles.PubSub,
  live_view: [signing_salt: "KSN+mBcj"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  marbles_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/marbles_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  marbles_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/marbles_web", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :ueberauth, Ueberauth,
  providers: [
    discord: {Ueberauth.Strategy.Discord, []}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
