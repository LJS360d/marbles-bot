defmodule Marbles.Leaderboards do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Inventory
  alias Marbles.Repo
  alias Marbles.Schema.{RaceQueueBot, User, UserIdentity, UserInventory, UserMarble}

  @type row :: %{rank: pos_integer(), user_id: Ecto.UUID.t(), label: String.t(), score: integer()}

  @spec top_coins(pos_integer()) :: [row()]
  def top_coins(limit \\ 10) when is_integer(limit) and limit > 0 do
    coins_subquery =
      from(ui in UserInventory,
        where: ui.item_type == ^Inventory.currency_item_type(),
        where: ui.item_id == ^Inventory.coins_item_id(),
        select: %{user_id: ui.user_id, quantity: ui.quantity}
      )

    from(u in User,
      as: :user,
      left_join: c in subquery(coins_subquery),
      on: c.user_id == u.id,
      left_join: i in UserIdentity,
      on: i.user_id == u.id and i.platform == "discord",
      order_by: [desc: coalesce(c.quantity, 0), asc: u.id],
      limit: ^limit,
      select: %{
        user_id: u.id,
        label: fragment("coalesce(?, ?, 'User')", i.username, u.display_name),
        score: coalesce(c.quantity, 0)
      }
    )
    |> exclude_bots()
    |> Repo.all()
    |> with_ranks()
  end

  @spec top_collection_count(pos_integer()) :: [row()]
  def top_collection_count(limit \\ 10) when is_integer(limit) and limit > 0 do
    sub =
      from(um in UserMarble,
        group_by: um.user_id,
        select: %{user_id: um.user_id, cnt: count(um.id)}
      )

    from(s in subquery(sub),
      join: u in User,
      as: :user,
      on: u.id == s.user_id,
      left_join: i in UserIdentity,
      on: i.user_id == u.id and i.platform == "discord",
      order_by: [desc: s.cnt, asc: u.id],
      limit: ^limit,
      select: %{
        user_id: u.id,
        label: fragment("coalesce(?, ?, 'User')", i.username, u.display_name),
        score: s.cnt
      }
    )
    |> exclude_bots()
    |> Repo.all()
    |> with_ranks()
  end

  @spec top_strongest_marble(pos_integer()) :: [row()]
  def top_strongest_marble(limit \\ 10) when is_integer(limit) and limit > 0 do
    sub =
      from(um in UserMarble,
        group_by: um.user_id,
        select: %{
          user_id: um.user_id,
          best: max(fragment("( ? * 1000000000 + ? )", um.level, um.experience))
        }
      )

    from(s in subquery(sub),
      join: u in User,
      as: :user,
      on: u.id == s.user_id,
      left_join: i in UserIdentity,
      on: i.user_id == u.id and i.platform == "discord",
      order_by: [desc: s.best, asc: u.id],
      limit: ^limit,
      select: %{
        user_id: u.id,
        label: fragment("coalesce(?, ?, 'User')", i.username, u.display_name),
        score: s.best
      }
    )
    |> exclude_bots()
    |> Repo.all()
    |> with_ranks()
  end

  defp with_ranks(rows),
    do: Enum.with_index(rows, 1) |> Enum.map(fn {m, i} -> Map.put(m, :rank, i) end)

  defp exclude_bots(query) do
    bot_ids = from(b in RaceQueueBot, select: b.user_id)
    where(query, [user: u], u.id not in subquery(bot_ids))
  end
end
