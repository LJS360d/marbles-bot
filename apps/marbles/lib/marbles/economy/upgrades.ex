defmodule Marbles.Economy.Upgrades do
  @moduledoc false

  alias Marbles.Repo
  alias Marbles.Schema.{User, UserUpgrade}
  alias Marbles.Accounts

  @type upgrade_key :: String.t()

  @spec definitions() :: map()
  def definitions do
    %{
      "mine_yield" => %{
        title: "Mine yield",
        max_level: 5,
        costs: [20, 45, 90, 160, 280],
        yield_percent_per_level: 5
      },
      "mine_cap" => %{
        title: "Offline mine cap",
        max_level: 5,
        costs: [18, 40, 75, 130, 220],
        extra_hours_per_level: 4
      },
      "dust_gain" => %{
        title: "Duplicate dust",
        max_level: 5,
        costs: [22, 50, 95, 170, 300],
        dust_percent_per_level: 8
      },
      "spawn_luck" => %{
        title: "Spawn catch luck",
        max_level: 5,
        costs: [16, 38, 72, 120, 200],
        luck_per_level: 0.01
      }
    }
  end

  @spec valid_key?(String.t()) :: boolean()
  def valid_key?(key) when is_binary(key), do: Map.has_key?(definitions(), key)
  def valid_key?(_), do: false

  @spec level(Ecto.UUID.t(), upgrade_key()) :: non_neg_integer()
  def level(user_id, key) do
    case Repo.get_by(UserUpgrade, user_id: user_id, upgrade_key: key) do
      nil -> 0
      %{level: l} when is_integer(l) and l >= 0 -> l
    end
  end

  @spec mine_yield_percent(Ecto.UUID.t()) :: non_neg_integer()
  def mine_yield_percent(user_id) do
    level(user_id, "mine_yield") * definitions()["mine_yield"].yield_percent_per_level
  end

  @spec mine_extra_offline_hours(Ecto.UUID.t()) :: non_neg_integer()
  def mine_extra_offline_hours(user_id) do
    level(user_id, "mine_cap") * definitions()["mine_cap"].extra_hours_per_level
  end

  @spec dust_gain_percent(Ecto.UUID.t()) :: non_neg_integer()
  def dust_gain_percent(user_id) do
    level(user_id, "dust_gain") * definitions()["dust_gain"].dust_percent_per_level
  end

  @spec spawn_luck_bonus(Ecto.UUID.t()) :: float()
  def spawn_luck_bonus(user_id) do
    level(user_id, "spawn_luck") * definitions()["spawn_luck"].luck_per_level
  end

  @spec buy(Ecto.UUID.t(), upgrade_key()) ::
          {:ok, %{key: upgrade_key(), new_level: non_neg_integer()}}
          | {:error, :invalid_key | :maxed | :insufficient_dust}
  def buy(user_id, key) when is_binary(key) do
    if not valid_key?(key) do
      {:error, :invalid_key}
    else
      defn = definitions()[key]
      cur = level(user_id, key)

      if cur >= defn.max_level do
        {:error, :maxed}
      else
        cost = Enum.at(defn.costs, cur)

        case Repo.transaction(fn ->
               user = Repo.get!(User, user_id)

               if user.dust < cost do
                 Repo.rollback(:insufficient_dust)
               end

               {:ok, _} = Accounts.update_dust(user, -cost)
               new_level = cur + 1

               case Repo.get_by(UserUpgrade, user_id: user_id, upgrade_key: key) do
                 nil ->
                   %UserUpgrade{}
                   |> UserUpgrade.changeset(%{
                     user_id: user_id,
                     upgrade_key: key,
                     level: new_level
                   })
                   |> Repo.insert!()

                 row ->
                   row
                   |> UserUpgrade.changeset(%{level: new_level})
                   |> Repo.update!()
               end

               %{key: key, new_level: new_level}
             end) do
          {:ok, m} -> {:ok, m}
          {:error, :insufficient_dust} -> {:error, :insufficient_dust}
          other -> other
        end
      end
    end
  end
end
