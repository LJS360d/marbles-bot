defmodule MarblesWeb.Discord.ActivityAuthController do
  use MarblesWeb, :controller

  alias Marbles.{Accounts, Analytics}

  @spec exchange(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def exchange(conn, %{"code" => code}) when is_binary(code) and code != "" do
    oauth_module =
      Application.get_env(
        :marbles_web,
        :discord_activity_oauth_module,
        MarblesWeb.Discord.ActivityOAuth
      )

    case oauth_module.exchange_code_for_user(code) do
      {:ok, attrs} ->
        case Accounts.ensure_user(attrs) do
          {:ok, user} ->
            Analytics.record_event("discord_activity_auth_success", nil, nil, user.id, %{
              "source" => "discord_activity"
            })

            conn
            |> configure_session(renew: true)
            |> put_session(:user_id, user.id)
            |> json(%{
              ok: true,
              user: %{id: user.id, display_name: Accounts.primary_display_name(user)}
            })

          {:error, _changeset} ->
            Analytics.record_event("discord_activity_auth_failed", nil, nil, nil, %{
              "source" => "discord_activity",
              "reason" => "ensure_user_failed"
            })

            conn
            |> put_status(:internal_server_error)
            |> json(%{ok: false, error: "user_creation_failed"})
        end

      {:error, reason} ->
        Analytics.record_event("discord_activity_auth_failed", nil, nil, nil, %{
          "source" => "discord_activity",
          "reason" => inspect(reason)
        })

        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "oauth_exchange_failed"})
    end
  end

  def exchange(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{ok: false, error: "missing_code"})
  end
end
