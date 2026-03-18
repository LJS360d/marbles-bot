import Config
import Dotenvy

source!([".env", System.get_env()]) |> System.put_env()

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

config :marbles_web, MarblesWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :nostrum,
  token:
    System.get_env("DISCORD_BOT_TOKEN") ||
      raise("""
      environment variable DISCORD_BOT_TOKEN is missing.
      """)

config :nostrum, youtubedl: nil
config :nostrum, streamlink: nil

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: System.get_env("DISCORD_OAUTH_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_OAUTH_CLIENT_SECRET")

owner_platform_ids = System.get_env("OWNER_USER_IDS", "") |> String.split(",", trim: true)
config :marbles_web, :owner_platform_ids, owner_platform_ids
config :marbles, :owner_platform_ids, owner_platform_ids

assets_base_url = System.get_env("ASSETS_BASE_URL")

if config_env() == :prod do
  # In Prod, we use SeaweedFS/S3
  if is_nil(assets_base_url) or assets_base_url == "" do
    raise "environment variable ASSETS_BASE_URL is required in production."
  end

  config :marbles, :storage_adapter, Marbles.Storage.S3

  # ExAws Configuration for SeaweedFS
  config :ex_aws,
    # Seaweed ignores these 3 but library needs it
    http_client: ExAws.Request.Req,
    access_key_id: System.get_env("S3_ACCESS_KEY", "any"),
    secret_access_key: System.get_env("S3_SECRET_KEY", "any"),
    region: "us-east-1",
    s3: [
      scheme: "http://",
      host: System.get_env("S3_HOST", "bucket"),
      port: 8333,
      # Requirement for SeaweedFS
      path_style: true
    ]
else
  # In Dev, we use cloudflare r2
  config :marbles, :storage_adapter, Marbles.Storage.S3

  # ExAws Configuration for Cloudflare R2
  config :ex_aws,
    http_client: ExAws.Request.Req,
    access_key_id: System.get_env("S3_ACCESS_KEY", "any"),
    secret_access_key: System.get_env("S3_SECRET_KEY", "any"),
    region: System.get_env("S3_REGION", "auto"),
    s3: [
      scheme: System.get_env("S3_SCHEME", "https://"),
      host: System.get_env("S3_HOST", "bucket"),
      port: 443,
      path_style: System.get_env("S3_PATH_STYLE", "true") == "true"
    ]
end

config :marbles, :assets_base_url, assets_base_url

if config_env() == :prod and (is_nil(assets_base_url) or assets_base_url == "") do
  raise """
  environment variable ASSETS_BASE_URL is required in production.
  Set it to the base URL where asset paths are served (e.g. CDN or bucket URL).
  """
end

if assets_base_url != nil and assets_base_url != "" do
  config :marbles, :assets_base_url, assets_base_url
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :marbles, Marbles.Repo,
    url: database_url,
    # SSL is usually required for external DBs, but since we are in
    # the same Docker network as Postgres, we can keep it simple.
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: [:inet6]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :marbles_web, MarblesWeb.Endpoint,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## Using releases
  #
  # If you are doing OTP releases, you need to instruct Phoenix
  # to start each relevant endpoint:
  #
  #     config :marbles_web, MarblesWeb.Endpoint, server: true
  #
  # Then you can assemble a release by calling `mix release`.
  # See `mix help release` for more information.

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :marbles_web, MarblesWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :marbles_web, MarblesWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :marbles, Marbles.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  config :marbles, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
