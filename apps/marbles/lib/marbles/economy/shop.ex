defmodule Marbles.Economy.Shop do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.{User, UserEffect, ShopItem}
  alias Marbles.Accounts

  @type product_id :: String.t()

  @spec default_products() :: [map()]
  def default_products do
    [
      %{
        id: "mine_yield_boost_24h",
        name: "+15% mine yield (24h)",
        coin: 400,
        dust: 0,
        duration_sec: 86_400,
        limit_count: 3,
        limit_period_unit: "week",
        effect_key: "boost_mine_yield",
        meta: %{"pct" => 15}
      },
      %{
        id: "mine_cap_boost_24h",
        name: "+8h offline mine cap (24h)",
        coin: 350,
        dust: 0,
        duration_sec: 86_400,
        limit_count: 3,
        limit_period_unit: "week",
        effect_key: "boost_mine_cap",
        meta: %{"hours" => 8}
      },
      %{
        id: "dust_gain_boost_24h",
        name: "+20% duplicate dust (24h)",
        coin: 0,
        dust: 180,
        duration_sec: 86_400,
        limit_count: 3,
        limit_period_unit: "week",
        effect_key: "boost_dust_gain",
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

  @spec purchases_in_period(Ecto.UUID.t(), map()) :: non_neg_integer()
  def purchases_in_period(user_id, product) do
    start = period_start_utc(product.limit_period_unit || "week")
    effect_prefix = product.effect_key

    from(e in UserEffect,
      where: e.user_id == ^user_id and e.inserted_at >= ^start,
      where: like(e.effect_key, ^"#{effect_prefix}%")
    )
    |> Repo.aggregate(:count, :id)
  end

  @spec period_label(String.t()) :: String.t()
  def period_label("day"), do: "day"
  def period_label("month"), do: "month"
  def period_label(_), do: "week"

  defp period_start_utc("day") do
    Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp period_start_utc("month") do
    d = Date.utc_today()
    Date.new!(d.year, d.month, 1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
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

    cond do
      is_nil(product) ->
        {:error, :invalid_product}

      purchases_in_period(user_id, product) >= (product.limit_count || 3) ->
        {:error, :period_limit}

      true ->
        case Repo.transaction(fn ->
               user = Repo.get!(User, user_id)

               cond do
                 user.currency < product.coin ->
                   Repo.rollback(:insufficient_coins)

                 user.dust < product.dust ->
                   Repo.rollback(:insufficient_dust)

                 true ->
                   :ok
               end

               if product.coin > 0, do: {:ok, _} = Accounts.update_currency(user, -product.coin)
               if product.dust > 0, do: {:ok, _} = Accounts.update_dust(user, -product.dust)

               expires_at = DateTime.utc_now() |> DateTime.add(product.duration_sec, :second)
               suffix = :rand.uniform(999_999_999) |> to_string()

               %UserEffect{}
               |> UserEffect.changeset(%{
                 user_id: user_id,
                 effect_key: product.effect_key <> "_" <> suffix,
                 scope: "account",
                 guild_id: nil,
                 expires_at: expires_at,
                 meta:
                   product.meta
                   |> Map.put("product_id", product.id)
                   |> Map.put("source", "shop")
               })
               |> Repo.insert!()
             end) do
          {:ok, %UserEffect{} = e} -> {:ok, e}
          {:error, :insufficient_coins} -> {:error, :insufficient_coins}
          {:error, :insufficient_dust} -> {:error, :insufficient_dust}
          other -> other
        end
    end
  end

  defp present?(nil), do: false
  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: true
end
