defmodule Marbles.Economy.Effects do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.UserEffect

  @spec list_active(Ecto.UUID.t()) :: [UserEffect.t()]
  def list_active(user_id) do
    now = DateTime.utc_now()

    from(e in UserEffect,
      where: e.user_id == ^user_id and e.expires_at > ^now
    )
    |> Repo.all()
  end

  @spec mine_yield_bonus_percent(Ecto.UUID.t()) :: non_neg_integer()
  def mine_yield_bonus_percent(user_id) do
    user_id
    |> list_active()
    |> Enum.filter(&String.starts_with?(&1.effect_key, "boost_mine_yield"))
    |> Enum.reduce(0, fn e, acc -> acc + meta_int(e.meta, "pct") end)
  end

  @spec mine_offline_cap_bonus_hours(Ecto.UUID.t()) :: non_neg_integer()
  def mine_offline_cap_bonus_hours(user_id) do
    user_id
    |> list_active()
    |> Enum.filter(&String.starts_with?(&1.effect_key, "boost_mine_cap"))
    |> Enum.reduce(0, fn e, acc -> acc + meta_int(e.meta, "hours") end)
  end

  @spec dust_gain_bonus_percent(Ecto.UUID.t()) :: non_neg_integer()
  def dust_gain_bonus_percent(user_id) do
    user_id
    |> list_active()
    |> Enum.filter(&String.starts_with?(&1.effect_key, "boost_dust_gain"))
    |> Enum.reduce(0, fn e, acc -> acc + meta_int(e.meta, "pct") end)
  end

  @spec exp_gain_bonus_percent(Ecto.UUID.t()) :: non_neg_integer()
  def exp_gain_bonus_percent(user_id) do
    user_id
    |> list_active()
    |> Enum.filter(&String.starts_with?(&1.effect_key, "boost_exp_gain"))
    |> Enum.reduce(0, fn e, acc -> acc + meta_int(e.meta, "pct") end)
  end

  defp meta_int(meta, k) when is_map(meta) do
    v = Map.get(meta, k) || Map.get(meta, String.to_atom(k))

    case v do
      i when is_integer(i) and i >= 0 -> i
      _ -> 0
    end
  end

  defp meta_int(_, _), do: 0

  @doc "Lists all currently-active effects across all users. Admin use."
  @spec list_all_active(non_neg_integer(), non_neg_integer()) ::
          {[UserEffect.t()], non_neg_integer()}
  def list_all_active(limit \\ 100, offset \\ 0) do
    now = DateTime.utc_now()
    base = from(e in UserEffect, where: e.expires_at > ^now)
    total = Repo.aggregate(base, :count, :id)

    entries =
      base
      |> order_by([e], asc: e.expires_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {entries, total}
  end

  @doc "Revokes (deletes) a single effect."
  @spec revoke(Ecto.UUID.t()) :: {:ok, UserEffect.t()} | {:error, :not_found}
  def revoke(id) do
    case Repo.get(UserEffect, id) do
      nil -> {:error, :not_found}
      eff -> Repo.delete(eff)
    end
  end

  @doc "Extends expiry of an effect by the given seconds."
  @spec extend(Ecto.UUID.t(), pos_integer()) ::
          {:ok, UserEffect.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def extend(id, seconds) when is_integer(seconds) and seconds > 0 do
    case Repo.get(UserEffect, id) do
      nil ->
        {:error, :not_found}

      eff ->
        new_expiry = DateTime.add(eff.expires_at, seconds, :second)

        eff
        |> Ecto.Changeset.change(%{expires_at: new_expiry})
        |> Repo.update()
    end
  end
end
