defmodule MarblesWeb.Discord.ActivityAuthControllerTest do
  use MarblesWeb.ConnCase, async: false

  setup do
    previous_module = Application.get_env(:marbles_web, :discord_activity_oauth_module)

    Application.put_env(
      :marbles_web,
      :discord_activity_oauth_module,
      MarblesWeb.TestSupport.DiscordActivityOAuthFake
    )

    on_exit(fn ->
      if previous_module do
        Application.put_env(:marbles_web, :discord_activity_oauth_module, previous_module)
      else
        Application.delete_env(:marbles_web, :discord_activity_oauth_module)
      end
    end)

    :ok
  end

  test "creates session and returns user on successful code exchange", %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post(~p"/api/discord/activity/exchange", %{"code" => "good"})

    assert %{"ok" => true, "user" => %{"id" => user_id}} = json_response(conn, 200)
    assert get_session(conn, :user_id) == user_id
  end

  test "returns unauthorized when exchange fails", %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post(~p"/api/discord/activity/exchange", %{"code" => "bad"})

    assert %{"ok" => false, "error" => "oauth_exchange_failed"} = json_response(conn, 401)
  end
end
