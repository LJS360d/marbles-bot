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

  defp meta_int(meta, k) when is_map(meta) do
    v = Map.get(meta, k) || Map.get(meta, String.to_atom(k))

    case v do
      i when is_integer(i) and i >= 0 -> i
      _ -> 0
    end
  end

  defp meta_int(_, _), do: 0
end
