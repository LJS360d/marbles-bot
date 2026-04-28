defmodule Marbles.EconomyTest do
  use Marbles.DataCase, async: true

  alias Marbles.Repo
  alias Marbles.Schema.{Marble, Team}
  alias Marbles.{Accounts, Collection}
  alias Marbles.Economy.{SpawnRewards, Mining, Upgrades, Admin}
  alias Marbles.Schema.UserDailyStreak

  setup do
    team =
      %Team{}
      |> Team.changeset(%{name: "T#{:rand.uniform(999_999)}"})
      |> Repo.insert!()

    marble =
      %Marble{}
      |> Marble.changeset(%{
        name: "M#{:rand.uniform(999_999)}",
        edition: "standard",
        role: :athlete,
        rarity: 2,
        base_stats: %{},
        team_id: team.id
      })
      |> Repo.insert!()

    {:ok, user} =
      Accounts.ensure_user(%{
        platform_id: "discord-#{:rand.uniform(999_999)}",
        platform: "discord",
        username: "u"
      })

    %{user: user, marble: marble}
  end

  test "duplicate template grants dust", %{user: user, marble: marble} do
    assert {:new, _} = Collection.acquire_marble_template(user.id, marble.id)
    assert {:duplicate, dust, _} = Collection.acquire_marble_template(user.id, marble.id)
    assert dust > 0
    assert Accounts.dust_balance(user.id) == dust
  end

  test "high spawn rate usually pays zero coins", %{marble: marble} do
    :rand.seed(:exsss, {1, 2, 3})
    rolls = for _ <- 1..80, do: SpawnRewards.roll_coins(95.0, marble.rarity || 1, 0.0)
    zeros = Enum.count(rolls, &(&1 == 0))
    assert zeros >= 55
  end

  test "mining accrual respects cap", %{user: user} do
    cap = Mining.max_accrual_seconds(user.id)
    past = DateTime.utc_now() |> DateTime.add(-(cap + 3600), :second)
    now = DateTime.utc_now()
    sec = Mining.accrual_seconds(past, now, user.id)
    assert sec == cap
  end

  test "mining reports roster size when accrual window is zero (e.g. first daily)", %{
    user: user,
    marble: marble
  } do
    assert {:new, um} = Collection.acquire_marble_template(user.id, marble.id)
    {:ok, _} = Accounts.update_user(user, %{mine_roster: %{"slots" => [to_string(um.id)]}})

    result = Mining.compute_coins(user.id, 0)
    assert result.coins == 0
    assert result.seconds == 0
    assert result.roster_size == 1
  end

  test "reset_daily_cooldown moves last claim off today", %{user: user} do
    now = DateTime.utc_now()

    %UserDailyStreak{}
    |> UserDailyStreak.changeset(%{
      user_id: user.id,
      last_claimed_at: now,
      current_streak: 3,
      longest_streak: 3
    })
    |> Repo.insert!()

    assert :ok = Admin.reset_daily_cooldown(user.id)

    row = Repo.get_by!(UserDailyStreak, user_id: user.id)
    assert Date.compare(DateTime.to_date(row.last_claimed_at), Date.utc_today()) == :lt
  end

  test "upgrade buy deducts dust", %{user: user} do
    {:ok, u} = Accounts.update_dust(user, 500)
    assert {:ok, %{new_level: 1}} = Upgrades.buy(u.id, "mine_yield")
    assert Accounts.dust_balance(u.id) < 500
  end
end
