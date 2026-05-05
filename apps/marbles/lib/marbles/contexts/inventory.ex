defmodule Marbles.Inventory do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.UserInventory

  @currency_item_type "currency"
  @coins_item_id "coins"
  @dust_item_id "dust"

  @type item_type :: String.t()
  @type item_id :: String.t()
  @type quantity :: non_neg_integer()
  @type item_key :: {item_type(), item_id()}
  @type item_reward :: %{
          required(:item_type) => item_type(),
          required(:item_id) => item_id(),
          required(:quantity) => pos_integer(),
          optional(:meta) => map()
        }

  @spec currency_item_type() :: String.t()
  def currency_item_type, do: @currency_item_type

  @spec coins_item_id() :: String.t()
  def coins_item_id, do: @coins_item_id

  @spec dust_item_id() :: String.t()
  def dust_item_id, do: @dust_item_id

  @spec currency_item_key(:coins | :dust) :: item_key()
  def currency_item_key(:coins), do: {@currency_item_type, @coins_item_id}
  def currency_item_key(:dust), do: {@currency_item_type, @dust_item_id}

  @spec ensure_default_currency_entries(Ecto.UUID.t()) :: :ok
  def ensure_default_currency_entries(user_id) when is_binary(user_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows = [
      %{
        id: Ecto.UUID.generate(),
        user_id: user_id,
        item_type: @currency_item_type,
        item_id: @coins_item_id,
        quantity: 0,
        meta: %{},
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ecto.UUID.generate(),
        user_id: user_id,
        item_type: @currency_item_type,
        item_id: @dust_item_id,
        quantity: 0,
        meta: %{},
        inserted_at: now,
        updated_at: now
      }
    ]

    Repo.insert_all(UserInventory, rows,
      on_conflict: :nothing,
      conflict_target: [:user_id, :item_type, :item_id]
    )

    :ok
  end

  @spec list_user_items(Ecto.UUID.t()) :: [UserInventory.t()]
  def list_user_items(user_id) when is_binary(user_id) do
    from(ui in UserInventory,
      where: ui.user_id == ^user_id,
      order_by: [asc: ui.item_type, asc: ui.item_id]
    )
    |> Repo.all()
  end

  @spec get_item_quantity(Ecto.UUID.t(), item_type(), item_id()) :: quantity()
  def get_item_quantity(user_id, item_type, item_id)
      when is_binary(user_id) and is_binary(item_type) and is_binary(item_id) do
    case Repo.get_by(UserInventory, user_id: user_id, item_type: item_type, item_id: item_id) do
      %UserInventory{quantity: q} when is_integer(q) and q > 0 -> q
      _ -> 0
    end
  end

  @spec get_currency_balance(Ecto.UUID.t(), :coins | :dust) :: quantity()
  def get_currency_balance(user_id, currency)
      when is_binary(user_id) and currency in [:coins, :dust] do
    {item_type, item_id} = currency_item_key(currency)
    get_item_quantity(user_id, item_type, item_id)
  end

  @spec get_currency_balances(Ecto.UUID.t()) :: %{coins: quantity(), dust: quantity()}
  def get_currency_balances(user_id) when is_binary(user_id) do
    rows =
      from(ui in UserInventory,
        where: ui.user_id == ^user_id and ui.item_type == ^@currency_item_type,
        where: ui.item_id in [^@coins_item_id, ^@dust_item_id],
        select: {ui.item_id, ui.quantity}
      )
      |> Repo.all()
      |> Map.new()

    %{
      coins: max(0, Map.get(rows, @coins_item_id, 0)),
      dust: max(0, Map.get(rows, @dust_item_id, 0))
    }
  end

  @spec currency_balances_for_users([Ecto.UUID.t()]) :: %{
          optional(Ecto.UUID.t()) => %{coins: quantity(), dust: quantity()}
        }
  def currency_balances_for_users(user_ids) when is_list(user_ids) do
    ids = Enum.uniq(Enum.filter(user_ids, &is_binary/1))

    if ids == [] do
      %{}
    else
      rows =
        from(ui in UserInventory,
          where: ui.user_id in ^ids and ui.item_type == ^@currency_item_type,
          where: ui.item_id in [^@coins_item_id, ^@dust_item_id],
          select: {ui.user_id, ui.item_id, ui.quantity}
        )
        |> Repo.all()

      Enum.reduce(
        rows,
        Enum.reduce(ids, %{}, fn user_id, acc ->
          Map.put(acc, user_id, %{coins: 0, dust: 0})
        end),
        fn {user_id, item_id, qty}, acc ->
          current = Map.get(acc, user_id, %{coins: 0, dust: 0})

          updated =
            case item_id do
              @coins_item_id -> %{current | coins: max(0, qty)}
              @dust_item_id -> %{current | dust: max(0, qty)}
              _ -> current
            end

          Map.put(acc, user_id, updated)
        end
      )
    end
  end

  @spec grant_item(Ecto.UUID.t(), item_type(), item_id(), pos_integer(), map()) ::
          {:ok, quantity()} | {:error, :invalid_quantity | Ecto.Changeset.t()}
  def grant_item(user_id, item_type, item_id, quantity, meta \\ %{})
      when is_binary(user_id) and is_binary(item_type) and is_binary(item_id) do
    if is_integer(quantity) and quantity > 0 do
      attrs = %{
        user_id: user_id,
        item_type: item_type,
        item_id: item_id,
        quantity: quantity,
        meta: meta
      }

      case %UserInventory{}
           |> UserInventory.changeset(attrs)
           |> Repo.insert(
             on_conflict: [inc: [quantity: quantity]],
             conflict_target: [:user_id, :item_type, :item_id]
           ) do
        {:ok, _} -> {:ok, get_item_quantity(user_id, item_type, item_id)}
        {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
      end
    else
      {:error, :invalid_quantity}
    end
  end

  @spec spend_item(Ecto.UUID.t(), item_type(), item_id(), pos_integer()) ::
          {:ok, quantity()} | {:error, :insufficient_quantity | :invalid_quantity}
  def spend_item(user_id, item_type, item_id, quantity)
      when is_binary(user_id) and is_binary(item_type) and is_binary(item_id) do
    if is_integer(quantity) and quantity > 0 do
      {updated, _} =
        from(ui in UserInventory,
          where:
            ui.user_id == ^user_id and ui.item_type == ^item_type and ui.item_id == ^item_id and
              ui.quantity >= ^quantity
        )
        |> Repo.update_all(inc: [quantity: -quantity])

      if updated == 1 do
        {:ok, get_item_quantity(user_id, item_type, item_id)}
      else
        {:error, :insufficient_quantity}
      end
    else
      {:error, :invalid_quantity}
    end
  end

  @spec change_item_quantity(Ecto.UUID.t(), item_type(), item_id(), integer(), map()) ::
          {:ok, quantity()}
          | {:error, :insufficient_quantity | :invalid_quantity | Ecto.Changeset.t()}
  def change_item_quantity(user_id, item_type, item_id, delta, meta \\ %{})
      when is_binary(user_id) and is_binary(item_type) and is_binary(item_id) and
             is_integer(delta) do
    cond do
      delta > 0 -> grant_item(user_id, item_type, item_id, delta, meta)
      delta < 0 -> spend_item(user_id, item_type, item_id, abs(delta))
      true -> {:ok, get_item_quantity(user_id, item_type, item_id)}
    end
  end

  @spec set_item_quantity(Ecto.UUID.t(), item_type(), item_id(), non_neg_integer(), map()) ::
          {:ok, quantity()}
          | {:error, :insufficient_quantity | :invalid_quantity | Ecto.Changeset.t()}
  def set_item_quantity(user_id, item_type, item_id, desired, meta \\ %{})
      when is_binary(user_id) and is_binary(item_type) and is_binary(item_id) and
             is_integer(desired) and
             desired >= 0 do
    current = get_item_quantity(user_id, item_type, item_id)
    change_item_quantity(user_id, item_type, item_id, desired - current, meta)
  end

  @spec grant_rewards(Ecto.UUID.t(), [item_reward()]) ::
          {:ok, %{optional(item_key()) => quantity()}}
          | {:error, :invalid_quantity | Ecto.Changeset.t()}
  def grant_rewards(user_id, rewards) when is_binary(user_id) and is_list(rewards) do
    Enum.reduce_while(rewards, {:ok, %{}}, fn reward, {:ok, acc} ->
      item_type = Map.get(reward, :item_type) || Map.get(reward, "item_type")
      item_id = Map.get(reward, :item_id) || Map.get(reward, "item_id")
      quantity = Map.get(reward, :quantity) || Map.get(reward, "quantity")
      meta = Map.get(reward, :meta) || Map.get(reward, "meta") || %{}

      case grant_item(user_id, item_type, item_id, quantity, meta) do
        {:ok, current_qty} ->
          {:cont, {:ok, Map.put(acc, {item_type, item_id}, current_qty)}}

        {:error, :invalid_quantity} ->
          {:halt, {:error, :invalid_quantity}}

        {:error, %Ecto.Changeset{}} = err ->
          {:halt, err}
      end
    end)
  end
end
