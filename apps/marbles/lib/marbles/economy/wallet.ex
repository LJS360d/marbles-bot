defmodule Marbles.Economy.Wallet do
  @moduledoc false

  alias Marbles.Accounts

  @type funds :: %{coins: non_neg_integer(), dust: non_neg_integer()}
  @type cost :: %{optional(:coins) => non_neg_integer(), optional(:dust) => non_neg_integer()}
  @type debit_error :: :insufficient_coins | :insufficient_dust

  @spec balances(Ecto.UUID.t()) :: funds()
  def balances(user_id) do
    wallet = Accounts.wallet(user_id)
    %{coins: wallet.coins, dust: wallet.dust}
  end

  @spec ensure_affordable(Ecto.UUID.t(), cost()) :: :ok | {:error, debit_error()}
  def ensure_affordable(user_id, cost) when is_map(cost) do
    wallet = balances(user_id)
    coins = Map.get(cost, :coins, 0)
    dust = Map.get(cost, :dust, 0)

    cond do
      wallet.coins < coins -> {:error, :insufficient_coins}
      wallet.dust < dust -> {:error, :insufficient_dust}
      true -> :ok
    end
  end

  @spec debit(Ecto.UUID.t(), cost()) :: :ok | {:error, debit_error()}
  def debit(user_id, cost) when is_map(cost) do
    with :ok <- ensure_affordable(user_id, cost),
         %{} = user <- Accounts.get_user(user_id),
         :ok <- maybe_update_currency(user, -Map.get(cost, :coins, 0)),
         :ok <- maybe_update_dust(user, -Map.get(cost, :dust, 0)) do
      :ok
    end
  end

  @spec credit(Ecto.UUID.t(), cost()) :: :ok | {:error, :invalid_quantity}
  def credit(user_id, amount) when is_map(amount) do
    with %{} = user <- Accounts.get_user(user_id),
         :ok <- maybe_update_currency(user, Map.get(amount, :coins, 0)),
         :ok <- maybe_update_dust(user, Map.get(amount, :dust, 0)) do
      :ok
    end
  end

  @spec maybe_update_currency(map(), integer()) ::
          :ok | {:error, :insufficient_coins | :invalid_quantity}
  defp maybe_update_currency(_user, 0), do: :ok

  defp maybe_update_currency(user, delta) do
    case Accounts.update_currency(user, delta) do
      {:ok, _} -> :ok
      {:error, :insufficient_currency} -> {:error, :insufficient_coins}
      {:error, :invalid_quantity} -> {:error, :invalid_quantity}
    end
  end

  @spec maybe_update_dust(map(), integer()) ::
          :ok | {:error, :insufficient_dust | :invalid_quantity}
  defp maybe_update_dust(_user, 0), do: :ok

  defp maybe_update_dust(user, delta) do
    case Accounts.update_dust(user, delta) do
      {:ok, _} -> :ok
      {:error, :insufficient_dust} -> {:error, :insufficient_dust}
      {:error, :invalid_quantity} -> {:error, :invalid_quantity}
    end
  end
end
