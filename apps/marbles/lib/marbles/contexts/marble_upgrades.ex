defmodule Marbles.MarbleUpgrades do
  import Ecto.Query
  alias Marbles.{Inventory, Repo}
  alias Marbles.Schema.{MarbleUpgrade, UserMarble}

  @marble_core_item_type "material"
  @marble_core_item_id "marble_core"

  @type upgrade_result :: {:ok, UserMarble.t()} | {:error, atom()}

  @spec apply_marble_core(Ecto.UUID.t(), Ecto.UUID.t()) :: upgrade_result()
  def apply_marble_core(user_id, user_marble_id)
      when is_binary(user_id) and is_binary(user_marble_id) do
    Repo.transaction(fn ->
      user_marble = Repo.get!(UserMarble, user_marble_id)

      if user_marble.user_id != user_id do
        Repo.rollback(:unauthorized)
      end

      marble = Repo.get!(Marbles.Schema.Marble, user_marble.marble_id)

      if (marble.rarity || 1) != 3 do
        Repo.rollback(:not_3_star)
      end

      if core_already_applied?(user_marble_id) do
        Repo.rollback(:core_already_applied)
      end

      case Inventory.spend_item(user_id, @marble_core_item_type, @marble_core_item_id, 1) do
        {:ok, _} ->
          {:ok, _upgrade} = create_upgrade(user_marble_id, "marble_core")
          new_power_level = recalculate_power_level(user_marble_id)

          user_marble
          |> UserMarble.changeset(%{power_level: new_power_level})
          |> Repo.update!()

        {:error, _} ->
          Repo.rollback(:insufficient_marble_core)
      end
    end)
  end

  @spec core_already_applied?(Ecto.UUID.t()) :: boolean()
  defp core_already_applied?(user_marble_id) do
    from(u in MarbleUpgrade,
      where: u.user_marble_id == ^user_marble_id and u.upgrade_type == "marble_core"
    )
    |> Repo.exists?()
  end

  @spec create_upgrade(Ecto.UUID.t(), String.t()) :: {:ok, MarbleUpgrade.t()} | {:error, term()}
  defp create_upgrade(user_marble_id, upgrade_type) do
    %MarbleUpgrade{}
    |> MarbleUpgrade.changeset(%{user_marble_id: user_marble_id, upgrade_type: upgrade_type})
    |> Repo.insert()
  end

  @spec recalculate_power_level(Ecto.UUID.t()) :: float()
  defp recalculate_power_level(user_marble_id) do
    upgrades = list_upgrades(user_marble_id)

    Enum.reduce(upgrades, 1.0, fn upgrade, acc ->
      case upgrade.upgrade_type do
        "marble_core" -> acc * 1.15
        _ -> acc
      end
    end)
  end

  @spec list_upgrades(Ecto.UUID.t()) :: [MarbleUpgrade.t()]
  defp list_upgrades(user_marble_id) do
    from(u in MarbleUpgrade,
      where: u.user_marble_id == ^user_marble_id,
      order_by: [asc: u.inserted_at]
    )
    |> Repo.all()
  end

  @spec get_upgrades(Ecto.UUID.t()) :: [MarbleUpgrade.t()]
  def get_upgrades(user_marble_id) when is_binary(user_marble_id) do
    list_upgrades(user_marble_id)
  end
end
