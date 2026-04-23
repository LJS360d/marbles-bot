defmodule Marbles.Leaderboards do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.{User, UserIdentity, UserMarble}

  @type row :: %{rank: pos_integer(), user_id: Ecto.UUID.t(), label: String.t(), score: integer()}

  @spec top_coins(pos_integer()) :: [row()]
  def top_coins(limit \\ 10) when is_integer(limit) and limit > 0 do
    from(u in User,
      left_join: i in UserIdentity,
      on: i.user_id == u.id and i.platform == "discord",
      order_by: [desc: u.currency, asc: u.id],
      limit: ^limit,
      select: %{
        user_id: u.id,
        label: fragment("coalesce(?, ?, 'User')", i.username, u.display_name),
        score: u.currency
      }
    )
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
    |> Repo.all()
    |> with_ranks()
  end

  defp with_ranks(rows), do: Enum.with_index(rows, 1) |> Enum.map(fn {m, i} -> Map.put(m, :rank, i) end)
end
