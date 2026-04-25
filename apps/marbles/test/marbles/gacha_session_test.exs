defmodule Marbles.GachaSessionTest do
  use Marbles.DataCase, async: false

  alias Marbles.{Accounts, GachaSession, Repo}
  alias Marbles.Schema.{Marble, Pack, PackPullRule, Team, User, UserPackPullRuleState}

  setup do
    user = create_user("gacha-session-user")
    team = create_team()
    marble_one = create_marble(team, 1, "Starter")
    marble_three = create_marble(team, 3, "Legend")
    pack = create_pack([marble_one, marble_three], 100)

    %{user: user, pack: pack, marble_one: marble_one, marble_three: marble_three}
  end

  test "list_pullable_packs_for_web returns quote and pity line data", %{user: user, pack: pack} do
    create_pity_rule(pack, 2, 3)

    [entry | _] = GachaSession.list_pullable_packs_for_web(user.id)

    assert entry.pack.id == pack.id
    assert entry.quote_one.final_price == 100
    assert entry.quote_ten.final_price == 1_000
    assert is_binary(entry.pity_line)
  end

  test "execute_pull returns insufficient currency without mutation", %{user: user, pack: pack} do
    {:ok, _} = Accounts.update_currency(user, -user.currency)
    user = Repo.get!(User, user.id)

    assert {:error, {:insufficient_currency, 100, 0}} =
             GachaSession.execute_pull(user.id, pack.id, :one)

    assert Repo.get!(User, user.id).currency == 0
  end

  test "execute_pull respects pity state and yields guaranteed rarity", %{
    user: user,
    pack: pack,
    marble_three: marble_three
  } do
    pity_rule = create_pity_rule(pack, 2, 3)

    %UserPackPullRuleState{}
    |> UserPackPullRuleState.changeset(%{
      user_id: user.id,
      rule_id: pity_rule.id,
      pulls_accumulated: 1
    })
    |> Repo.insert!()

    assert {:ok, result} = GachaSession.execute_pull(user.id, pack.id, :one)
    [entry] = result.marbles
    assert entry.marble.id == marble_three.id
  end

  test "execute_pull rolls back cleanly when pull pool is empty", %{user: user} do
    empty_pack = create_pack([], 150)
    before_currency = Repo.get!(User, user.id).currency

    assert {:error, :pull_failed} = GachaSession.execute_pull(user.id, empty_pack.id, :one)

    assert Repo.get!(User, user.id).currency == before_currency
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
    |> Team.changeset(%{name: "T-#{System.unique_integer([:positive])}"})
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
        name: "Pack-#{System.unique_integer([:positive])}",
        description: "test pack",
        cost: cost
      })
      |> Repo.insert!()
      |> Repo.preload(:marbles)

    pack
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:marbles, marbles)
    |> Repo.update!()
    |> Repo.preload([:marbles, :pull_rules])
  end

  defp create_pity_rule(pack, every_n_pulls, min_rarity) do
    %PackPullRule{}
    |> PackPullRule.changeset(%{
      pack_id: pack.id,
      effect_type: "pity",
      trigger_type: "every_n_pulls",
      every_n_pulls: every_n_pulls,
      min_rarity: min_rarity,
      apply_1x: true,
      apply_10x: true
    })
    |> Repo.insert!()
  end
end
