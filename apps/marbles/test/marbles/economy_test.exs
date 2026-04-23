defmodule Marbles.EconomyTest do
  use Marbles.DataCase, async: true

  alias Marbles.Repo
  alias Marbles.Schema.{User, Marble, Team}
  alias Marbles.{Accounts, Collection}
  alias Marbles.Economy.{SpawnRewards, Mining, Upgrades}

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
    assert Repo.get!(User, user.id).dust == dust
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

  test "upgrade buy deducts dust", %{user: user} do
    {:ok, u} = Accounts.update_dust(user, 500)
    assert {:ok, %{new_level: 1}} = Upgrades.buy(u.id, "mine_yield")
    assert Repo.get!(User, u.id).dust < 500
  end
end
