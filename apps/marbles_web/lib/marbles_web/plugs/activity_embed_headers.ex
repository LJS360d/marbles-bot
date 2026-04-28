defmodule MarblesWeb.Plugs.ActivityEmbedHeaders do
  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    allowed_origins =
      Application.get_env(:marbles_web, :discord_activity, [])
      |> Keyword.get(:allowed_origins, [])
      |> Enum.reject(&(&1 in [nil, ""]))

    frame_ancestors =
      ["'self'" | allowed_origins]
      |> Enum.join(" ")

    csp =
      [
        "default-src 'self' https: data: blob:",
        "connect-src 'self' https: wss:",
        "img-src 'self' https: data: blob:",
        "media-src 'self' https: data: blob:",
        "script-src 'self' 'unsafe-inline' https:",
        "style-src 'self' 'unsafe-inline' https:",
        "frame-ancestors " <> frame_ancestors
      ]
      |> Enum.join("; ")

    conn
    |> delete_resp_header("x-frame-options")
    |> put_resp_header("content-security-policy", csp)
  end
end
