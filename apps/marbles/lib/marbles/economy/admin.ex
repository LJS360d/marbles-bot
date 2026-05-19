defmodule Marbles.Economy.Admin do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Inventory
  alias Marbles.Repo

  alias Marbles.Schema.{
    RaceQueueBot,
    ShopItem,
    UserDailyStreak,
    UserEffect,
    UserIdentity,
    UserInventory,
    UserUpgrade
  }

  alias Marbles.Economy.Shop

  @spec list_shop_items() :: [map()]
  def list_shop_items do
    overrides =
      Repo.all(ShopItem)
      |> Map.new(fn row -> {row.id, row} end)

    Enum.map(Shop.default_products(), fn product ->
      ov = Map.get(overrides, product.id)

      %{
        id: product.id,
        base_name: product.name,
        name: if(ov && present?(ov.label_override), do: ov.label_override, else: product.name),
        enabled: if(ov, do: ov.enabled, else: true),
        coin: if(ov && is_integer(ov.coin_price), do: ov.coin_price, else: product.coin),
        dust: if(ov && is_integer(ov.dust_price), do: ov.dust_price, else: product.dust),
        duration_sec:
          if(ov && is_integer(ov.duration_sec), do: ov.duration_sec, else: product.duration_sec),
        limit_count:
          if(ov && is_integer(ov.limit_count), do: ov.limit_count, else: product.limit_count),
        limit_period_unit:
          if(ov && present?(ov.limit_period_unit),
            do: ov.limit_period_unit,
            else: product.limit_period_unit
          ),
        effect_key: product.effect_key,
        meta: product.meta
      }
    end)
  end

  @spec upsert_shop_item(String.t(), map()) :: {:ok, ShopItem.t()} | {:error, Ecto.Changeset.t()}
  def upsert_shop_item(id, attrs) when is_binary(id) and is_map(attrs) do
    (Repo.get(ShopItem, id) || %ShopItem{id: id})
    |> ShopItem.changeset(Map.put(attrs, :id, id))
    |> Repo.insert_or_update()
  end

  @spec list_user_cooldowns(pos_integer(), pos_integer()) :: {[map()], non_neg_integer()}
  def list_user_cooldowns(page \\ 1, per_page \\ 20)
      when is_integer(page) and page > 0 and is_integer(per_page) and per_page > 0 do
    offset = (page - 1) * per_page
    wallet = wallet_subquery()

    users_q =
      from(u in Marbles.Schema.User,
        left_join: w in subquery(wallet),
        on: w.user_id == u.id,
        left_join: i in UserIdentity,
        on: i.user_id == u.id and i.platform == "discord",
        left_join: d in UserDailyStreak,
        on: d.user_id == u.id,
        left_join: b in RaceQueueBot,
        on: b.user_id == u.id,
        order_by: [asc: not is_nil(b.id), asc: i.username, asc: u.id],
        select: %{
          id: u.id,
          username: coalesce(i.username, u.display_name),
          currency: coalesce(w.coins, 0),
          dust: coalesce(w.dust, 0),
          last_daily_at: d.last_claimed_at,
          streak: d.current_streak,
          is_bot: not is_nil(b.id)
        }
      )

    total = Repo.aggregate(from(u in Marbles.Schema.User), :count, :id)

    rows =
      users_q
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&add_cooldown_fields/1)

    {rows, total}
  end

  @doc """
  Clears the `/daily` same-day lock for a user by moving `last_claimed_at` to the previous UTC date.

  Intended for owner tooling / testing. Does not delete the streak row; the next claim still
  follows normal streak rules relative to that synthetic timestamp.
  """
  @spec reset_daily_cooldown(Ecto.UUID.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def reset_daily_cooldown(user_id) when is_binary(user_id) do
    synthetic_prior =
      Date.utc_today()
      |> Date.add(-1)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    case Repo.get_by(UserDailyStreak, user_id: user_id) do
      nil ->
        :ok

      row ->
        row
        |> UserDailyStreak.changeset(%{last_claimed_at: synthetic_prior})
        |> Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, cs} -> {:error, cs}
        end
    end
  end

  @spec list_user_upgrades(Ecto.UUID.t()) :: [UserUpgrade.t()]
  def list_user_upgrades(user_id) when is_binary(user_id) do
    from(u in UserUpgrade, where: u.user_id == ^user_id, order_by: [asc: u.upgrade_key])
    |> Repo.all()
  end

  @spec set_user_upgrade_level(Ecto.UUID.t(), String.t(), non_neg_integer()) ::
          {:ok, UserUpgrade.t()} | {:error, Ecto.Changeset.t()}
  def set_user_upgrade_level(user_id, key, level)
      when is_binary(user_id) and is_binary(key) and is_integer(level) and level >= 0 do
    row =
      Repo.get_by(UserUpgrade, user_id: user_id, upgrade_key: key) ||
        %UserUpgrade{user_id: user_id}

    row
    |> UserUpgrade.changeset(%{user_id: user_id, upgrade_key: key, level: level})
    |> Repo.insert_or_update()
  end

  @spec list_user_effects(Ecto.UUID.t()) :: [UserEffect.t()]
  def list_user_effects(user_id) when is_binary(user_id) do
    from(e in UserEffect, where: e.user_id == ^user_id, order_by: [desc: e.inserted_at])
    |> Repo.all()
  end

  @spec grant_user_effect(Ecto.UUID.t(), String.t(), pos_integer()) ::
          {:ok, UserEffect.t()} | {:error, Ecto.Changeset.t()}
  def grant_user_effect(user_id, effect_key, duration_hours)
      when is_binary(user_id) and is_binary(effect_key) and is_integer(duration_hours) and
             duration_hours > 0 do
    expires_at = DateTime.utc_now() |> DateTime.add(duration_hours * 3600, :second)

    %UserEffect{}
    |> UserEffect.changeset(%{
      user_id: user_id,
      effect_key: effect_key,
      scope: "account",
      expires_at: expires_at,
      meta: %{"source" => "owner_admin"}
    })
    |> Repo.insert()
  end

  @spec delete_user_effect(Ecto.UUID.t()) :: :ok
  def delete_user_effect(effect_id) when is_binary(effect_id) do
    from(e in UserEffect, where: e.id == ^effect_id) |> Repo.delete_all()
    :ok
  end

  defp add_cooldown_fields(row) do
    now = DateTime.utc_now()

    sec_until_daily =
      case row.last_daily_at do
        nil ->
          0

        dt ->
          next_utc =
            dt
            |> DateTime.to_date()
            |> Date.add(1)
            |> DateTime.new!(~T[00:00:00], "Etc/UTC")

          max(0, DateTime.diff(next_utc, now, :second))
      end

    Map.put(row, :seconds_until_daily, sec_until_daily)
  end

  defp present?(nil), do: false
  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: true

  @spec wallet_subquery() :: Ecto.Query.t()
  defp wallet_subquery do
    from(ui in UserInventory,
      where: ui.item_type == ^Inventory.currency_item_type(),
      group_by: ui.user_id,
      select: %{
        user_id: ui.user_id,
        coins:
          fragment(
            "SUM(CASE WHEN ? = ? THEN ? ELSE 0 END)",
            ui.item_id,
            ^Inventory.coins_item_id(),
            ui.quantity
          ),
        dust:
          fragment(
            "SUM(CASE WHEN ? = ? THEN ? ELSE 0 END)",
            ui.item_id,
            ^Inventory.dust_item_id(),
            ui.quantity
          )
      }
    )
  end
end
