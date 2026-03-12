# Collection operations
defmodule Marbles.Collection do
  alias Marbles.Repo
  alias Marbles.Schema.{UserMarble, Marble}
  import Ecto.Query

  @per_page 10
  def per_page, do: @per_page

  def list_user_inventory(user_id, opts \\ []) do
    sort = Keyword.get(opts, :sort, :rarity_level_name)
    page = Keyword.get(opts, :page, 1)
    per = Keyword.get(opts, :per_page, @per_page)
    offset = (max(1, page) - 1) * per

    base =
      from(um in UserMarble,
        where: um.user_id == ^user_id,
        join: m in Marble,
        on: um.marble_id == m.id,
        preload: [marble: [:team, :assets]]
      )

    ordered =
      case sort do
        :level_desc ->
          from([um, m] in base, order_by: [desc: um.level, desc: um.id])

        :name_asc ->
          from([um, m] in base, order_by: [asc: m.name, asc: um.id])

        _ ->
          from([um, m] in base,
            order_by: [desc: m.rarity, desc: um.level, asc: m.name, asc: um.id]
          )
      end

    total = Repo.aggregate(from(um in UserMarble, where: um.user_id == ^user_id), :count, :id)
    items = ordered |> offset(^offset) |> limit(^per) |> Repo.all()
    {items, total}
  end

  def add_marble_to_collection(user_id, marble_id, meta \\ %{}) do
    %UserMarble{}
    |> UserMarble.changeset(%{
      user_id: user_id,
      marble_id: marble_id,
      meta: meta
    })
    |> Repo.insert()
  end

  def get_user_marble!(user_id, user_marble_id) do
    Repo.get_by!(UserMarble, id: user_marble_id, user_id: user_id)
    |> Repo.preload(marble: [:team, :assets])
  end
end
