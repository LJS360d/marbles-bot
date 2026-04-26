defmodule MarblesWeb.GachaLiveTest do
  use MarblesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marbles.{Accounts, Repo}
  alias Marbles.Schema.{Marble, Pack, Team}

  setup %{conn: conn} do
    team = create_team()
    m1 = create_marble(team, 1, "Live")
    m2 = create_marble(team, 2, "Live")
    m3 = create_marble(team, 3, "Live")
    pack = create_pack([m1, m2, m3], 125)
    user = create_user("gacha-live-user")

    %{conn: conn, pack: pack, user: user}
  end

  test "guest can browse and gets login gate on pull", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/gacha")

    assert has_element?(view, "#gacha-pack-carousel")
    assert has_element?(view, "#gacha-pull-one")

    view
    |> element("#gacha-pull-one")
    |> render_click()

    assert has_element?(view, "#login-modal")
    refute has_element?(view, "#gacha-confirm-modal")
  end

  test "authenticated user sees confirm modal with wallet math", %{conn: conn, user: user} do
    conn = log_in(conn, user.id)
    {:ok, view, _html} = live(conn, ~p"/gacha")

    view
    |> element("#gacha-pull-one")
    |> render_click()

    assert has_element?(view, "#gacha-confirm-modal")
    assert has_element?(view, "#gacha-wallet-before")
    assert has_element?(view, "#gacha-wallet-after")
  end

  test "skip-confirm path executes pull and reaches recap state", %{conn: conn, user: user} do
    conn = log_in(conn, user.id)
    {:ok, view, _html} = live(conn, ~p"/gacha")

    render_hook(view, "gacha_pref_loaded", %{"skip_confirm" => true})

    view
    |> element("#gacha-pull-one")
    |> render_click()

    refute has_element?(view, "#gacha-confirm-modal")
    assert has_element?(view, "#gacha-animation-skip")

    render_hook(view, "gacha_animation_done", %{})

    assert has_element?(view, "#gacha-pull-again")
    assert has_element?(view, "#gacha-back-to-packs")
  end

  defp log_in(conn, user_id) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user_id)
  end

  defp create_user(prefix) do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.ensure_user(%{
        platform_id: "#{prefix}-#{unique}",
        platform: "discord",
        username: "#{prefix}-#{unique}"
      })

    {:ok, funded_user} = Accounts.update_currency(user, 10_000)
    funded_user
  end

  defp create_team do
    %Team{}
    |> Team.changeset(%{name: "LT-#{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  defp create_marble(team, rarity, name_prefix) do
    %Marble{}
    |> Marble.changeset(%{
      name: "#{name_prefix}-#{System.unique_integer([:positive])}",
      edition: "standard",
      role: :athlete,
      rarity: rarity,
      base_stats: %{},
      team_id: team.id
    })
    |> Repo.insert!()
  end

  defp create_pack(marbles, cost) do
    pack =
      %Pack{}
      |> Pack.changeset(%{
        name: "LPack-#{System.unique_integer([:positive])}",
        description: "live test pack",
        cost: cost
      })
      |> Repo.insert!()
      |> Repo.preload(:marbles)

    pack
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:marbles, marbles)
    |> Repo.update!()
  end
end
