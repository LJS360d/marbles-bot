# Collection operations
defmodule Marbles.Collection do
  alias Marbles.Repo
  alias Marbles.Schema.UserMarble
  import Ecto.Query

  def list_user_inventory(user_id) do
    from(um in UserMarble,
      where: um.user_id == ^user_id,
      preload: [marble: [:team, :assets]],
      order_by: [desc: um.inserted_at]
    )
    |> Repo.all()
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
