defmodule MarblesWeb.Plugs.RuntimeSession do
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    discord_activity = Application.get_env(:marbles_web, :discord_activity, [])
    same_site = Keyword.get(discord_activity, :session_same_site, "Lax")
    secure = Keyword.get(discord_activity, :session_secure, same_site == "None")

    session_opts =
      opts
      |> Keyword.put(:same_site, same_site)
      |> Keyword.put(:secure, secure)

    Plug.Session.call(conn, Plug.Session.init(session_opts))
  end
end
