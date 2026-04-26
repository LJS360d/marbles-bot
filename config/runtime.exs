import Config

if Code.ensure_loaded?(Dotenvy) do
  alias Dotenvy
  Dotenvy.source!([".env", System.get_env()]) |> System.put_env()
end

infer_release_role_from_name = fn ->
  case System.get_env("RELEASE_NAME") do
    "bot" -> "bot"
    "web" -> "web"
    _ -> "all"
  end
end

release_role =
  case System.get_env("RELEASE_ROLE") do
    r when is_binary(r) ->
      case String.trim(r) do
        "" -> infer_release_role_from_name.()
        trimmed -> trimmed
      end

    _ ->
      infer_release_role_from_name.()
  end

config :marbles_web, MarblesWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

unless config_env() == :prod and release_role == "web" do
  config :nostrum,
    token:
      System.get_env("DISCORD_BOT_TOKEN") ||
        raise("""
        environment variable DISCORD_BOT_TOKEN is missing.
        """)

  config :nostrum, youtubedl: nil
  config :nostrum, streamlink: nil
  config :nostrum, ffmpeg: nil
end

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: System.get_env("DISCORD_OAUTH_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_OAUTH_CLIENT_SECRET")

owner_platform_ids = System.get_env("OWNER_USER_IDS", "") |> String.split(",", trim: true)
config :marbles_web, :owner_platform_ids, owner_platform_ids
config :marbles_web, :discord_server_invite, System.get_env("DISCORD_SERVER_INVITE_URL")
config :marbles_web, :discord_bot_invite, System.get_env("DISCORD_BOT_INVITE_URL")
config :marbles, :owner_platform_ids, owner_platform_ids

assets_base_url = System.get_env("ASSETS_BASE_URL")

if config_env() == :prod and (is_nil(assets_base_url) or assets_base_url == "") do
  raise """
  environment variable ASSETS_BASE_URL is required in production.
  Set it to the base URL where asset paths are served (e.g. CDN or public R2 URL).
  """
end

{s3_access, s3_secret, s3_host} =
  if config_env() == :prod do
    {
      System.get_env("S3_ACCESS_KEY") ||
        raise("environment variable S3_ACCESS_KEY is required in production."),
      System.get_env("S3_SECRET_KEY") ||
        raise("environment variable S3_SECRET_KEY is required in production."),
      System.get_env("S3_HOST") ||
        raise(
          "environment variable S3_HOST is required in production (e.g. <accountid>.r2.cloudflarestorage.com)."
        )
    }
  else
    {
      System.get_env("S3_ACCESS_KEY", "any"),
      System.get_env("S3_SECRET_KEY", "any"),
      System.get_env("S3_HOST", "bucket")
    }
  end

config :marbles, :storage_adapter, Marbles.Storage.S3

config :ex_aws,
  http_client: ExAws.Request.Req,
  access_key_id: s3_access,
  secret_access_key: s3_secret,
  region: System.get_env("S3_REGION", "auto"),
  s3: [
    scheme: System.get_env("S3_SCHEME", "https://"),
    host: s3_host,
    port: String.to_integer(System.get_env("S3_PORT", "443")),
    path_style: System.get_env("S3_PATH_STYLE", "true") == "true"
  ]

if assets_base_url not in [nil, ""] do
  config :marbles, :assets_base_url, assets_base_url
end

if config_env() == :prod do
  trim_env = fn key ->
    case System.get_env(key) do
      v when is_binary(v) -> String.trim(v)
      _ -> ""
    end
  end

  database_path =
    case trim_env.("DATABASE_PATH") do
      "" ->
        case trim_env.("RAILWAY_VOLUME_MOUNT_PATH") do
          "" -> "/app/data/prod.db"
          mount -> Path.join(mount, "prod.db")
        end

      path ->
        path
    end

  config :marbles, Marbles.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  if release_role in ["web", "all"] do
    secret_key_base =
      System.get_env("SECRET_KEY_BASE") ||
        raise """
        environment variable SECRET_KEY_BASE is missing.
        You can generate one by calling: mix phx.gen.secret
        """

    parse_hostname = fn raw ->
      raw = String.trim(raw)

      if raw == "" do
        nil
      else
        raw
        |> String.replace_prefix("https://", "")
        |> String.replace_prefix("http://", "")
        |> String.split("/", parts: 2)
        |> hd()
        |> String.split(":", parts: 2)
        |> hd()
      end
    end

    public_hostname =
      Enum.find_value(["PHX_HOST", "RAILWAY_PUBLIC_DOMAIN"], fn key ->
        case System.get_env(key) do
          v when is_binary(v) -> parse_hostname.(v)
          _ -> nil
        end
      end)

    endpoint_opts = [
      http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
      secret_key_base: secret_key_base,
      server: true,
      check_origin: :conn
    ]

    endpoint_opts =
      case public_hostname do
        h when is_binary(h) and h != "" ->
          Keyword.put(endpoint_opts, :url,
            host: h,
            port: String.to_integer(System.get_env("PHX_URL_PORT", "443")),
            scheme: System.get_env("PHX_SCHEME", "https")
          )

        _ ->
          endpoint_opts
      end

    config :marbles_web, MarblesWeb.Endpoint, endpoint_opts
  end

  config :marbles, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
