defmodule Marbles.Economy.Shop do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Economy.Currency
  alias Marbles.Repo
  alias Marbles.Schema.{UserEffect, ShopItem}
  alias Marbles.Analytics
  alias Marbles.Accounts

  @type product_id :: String.t()

  @spec default_products() :: [map()]
  def default_products do
    [
      %{
        id: "boost_mine_yield",
        name: "+15% Mining yield (24h)",
        coin: 400,
        dust: 0,
        duration_sec: 86_400,
        limit_count: 3,
        limit_period_unit: "week",
        effect_key: "boost_mine_yield",
        meta: %{"pct" => 15}
      },
      %{
        id: "boost_dust_gain",
        name: "+20% #{Currency.dust_emoji()} gain (24h)",
        coin: 0,
        dust: 180,
        duration_sec: 86_400,
        limit_count: 3,
        limit_period_unit: "week",
        effect_key: "boost_dust_gain",
        meta: %{"pct" => 20}
      },
      %{
        id: "boost_exp_gain",
        name: "+20% EXP gains (24h)",
        coin: 250,
        dust: 0,
        duration_sec: 86_400,
        limit_count: 3,
        limit_period_unit: "week",
        effect_key: "boost_exp_gain",
        meta: %{"pct" => 20}
      }
    ]
  end

  @spec products() :: [map()]
  def products do
    overrides =
      Repo.all(ShopItem)
      |> Map.new(fn row -> {row.id, row} end)

    default_products()
    |> Enum.reduce([], fn product, acc ->
      row = Map.get(overrides, product.id)
      enabled = if(row, do: row.enabled, else: true)

      if enabled do
        updated = %{
          product
          | name:
              if(row && present?(row.label_override), do: row.label_override, else: product.name),
            coin: if(row && is_integer(row.coin_price), do: row.coin_price, else: product.coin),
            dust: if(row && is_integer(row.dust_price), do: row.dust_price, else: product.dust),
            duration_sec:
              if(row && is_integer(row.duration_sec),
                do: row.duration_sec,
                else: product.duration_sec
              ),
            limit_count:
              if(row && is_integer(row.limit_count),
                do: row.limit_count,
                else: product.limit_count
              ),
            limit_period_unit:
              if(row && present?(row.limit_period_unit),
                do: row.limit_period_unit,
                else: product.limit_period_unit
              )
        }

        [updated | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  @spec valid_product?(product_id()) :: boolean()
  def valid_product?(id) when is_binary(id), do: Enum.any?(products(), &(&1.id == id))
  def valid_product?(_), do: false

  @doc """
  Human-readable name for an active shop effect (matches `products/0` names and overrides).
  """
  @spec effect_display_name(UserEffect.t()) :: String.t()
  def effect_display_name(%UserEffect{effect_key: key, meta: meta}) do
    meta = meta || %{}
    pid = Map.get(meta, "product_id")
    list = products()

    product =
      cond do
        is_binary(pid) and pid != "" ->
          Enum.find(list, &(&1.id == pid))

        true ->
          Enum.find(list, fn p -> String.starts_with?(key, p.effect_key <> "_") end)
      end

    case product do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> effect_display_name_fallback(key)
    end
  end

  defp effect_display_name_fallback(key) when is_binary(key) do
    legacy_name =
      cond do
        String.starts_with?(key, "boost_mine_cap_") -> "+8h Resources mining cap (24h)"
        true -> nil
      end

    if is_binary(legacy_name) do
      legacy_name
    else
      case Enum.find(default_products(), fn p -> String.starts_with?(key, p.effect_key <> "_") end) do
        %{name: n} when is_binary(n) -> n
        _ -> key
      end
    end
  end

  defp effect_display_name_fallback(_), do: "Unknown boost"

  @spec purchases_in_period(Ecto.UUID.t(), map()) :: non_neg_integer()
  def purchases_in_period(user_id, product) do
    limit_count = product.limit_count || 0

    if limit_count <= 0 do
      0
    else
      start = period_start_utc(product.limit_period_unit || "week")
      product_id = product.id

      from(e in UserEffect,
        where: e.user_id == ^user_id and e.inserted_at >= ^start,
        where: fragment("? ->> 'product_id' = ?", e.meta, ^product_id)
      )
      |> Repo.aggregate(:count, :id)
    end
  end

  @spec period_label(String.t()) :: String.t()
  def period_label("day"), do: "today"
  def period_label("month"), do: "this month"
  def period_label("year"), do: "this year"
  def period_label(_), do: "this week"

  defp period_start_utc("day") do
    Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp period_start_utc("month") do
    d = Date.utc_today()
    Date.new!(d.year, d.month, 1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp period_start_utc("year") do
    d = Date.utc_today()
    Date.new!(d.year, 1, 1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp period_start_utc(_) do
    d = Date.utc_today()
    dow = Date.day_of_week(d)
    days_back = dow - 1
    d |> Date.add(-days_back) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  @spec buy(Ecto.UUID.t(), product_id()) ::
          {:ok, UserEffect.t()}
          | {:error, :invalid_product | :period_limit | :insufficient_coins | :insufficient_dust}
  def buy(user_id, product_id) when is_binary(product_id) do
    product = Enum.find(products(), &(&1.id == product_id))
    limit_count = product && (product.limit_count || 0)

    cond do
      is_nil(product) ->
        {:error, :invalid_product}

      limit_count > 0 and purchases_in_period(user_id, product) >= limit_count ->
        {:error, :period_limit}

      true ->
        case Repo.transaction(fn ->
               user = Accounts.get_user!(user_id)
               wallet = Accounts.wallet(user_id)

               cond do
                 wallet.coins < product.coin ->
                   Repo.rollback(:insufficient_coins)

                 wallet.dust < product.dust ->
                   Repo.rollback(:insufficient_dust)

                 true ->
                   :ok
               end

               if product.coin > 0, do: {:ok, _} = Accounts.update_currency(user, -product.coin)
               if product.dust > 0, do: {:ok, _} = Accounts.update_dust(user, -product.dust)

               now = DateTime.utc_now()
               existing = active_product_effect(user_id, product.id, now)
               base_expiry = if existing, do: existing.expires_at, else: now
               expires_at = DateTime.add(base_expiry, product.duration_sec, :second)

               meta =
                 product.meta |> Map.put("product_id", product.id) |> Map.put("source", "shop")

               case existing do
                 %UserEffect{} = effect ->
                   effect
                   |> UserEffect.changeset(%{
                     expires_at: expires_at,
                     meta: Map.merge(effect.meta || %{}, meta)
                   })
                   |> Repo.update!()

                 nil ->
                   suffix = :rand.uniform(999_999_999) |> to_string()

                   %UserEffect{}
                   |> UserEffect.changeset(%{
                     user_id: user_id,
                     effect_key: product.effect_key <> "_" <> suffix,
                     scope: "account",
                     guild_id: nil,
                     expires_at: expires_at,
                     meta: meta
                   })
                   |> Repo.insert!()
               end
             end) do
          {:ok, %UserEffect{} = e} ->
            _ =
              Analytics.record_event("shop_buy", nil, nil, user_id, %{
                "product_id" => product.id,
                "effect_key" => product.effect_key,
                "coin_price" => product.coin,
                "dust_price" => product.dust,
                "duration_sec" => product.duration_sec
              })

            {:ok, e}

          {:error, :insufficient_coins} ->
            {:error, :insufficient_coins}

          {:error, :insufficient_dust} ->
            {:error, :insufficient_dust}

          other ->
            other
        end
    end
  end

  @spec active_product_effect(Ecto.UUID.t(), String.t(), DateTime.t()) :: UserEffect.t() | nil
  defp active_product_effect(user_id, product_id, now) do
    from(e in UserEffect,
      where: e.user_id == ^user_id and e.expires_at > ^now,
      where: fragment("? ->> 'product_id' = ?", e.meta, ^product_id),
      order_by: [desc: e.expires_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp present?(nil), do: false
  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: true
end
