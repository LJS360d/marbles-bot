# Read-only operations
defmodule Marbles.Catalog do
  alias Marbles.Repo
  alias Marbles.Schema.{Team, Marble}
  import Ecto.Query

  ## Teams
  def list_teams, do: Repo.all(Team)

  def get_team!(id), do: Repo.get!(Team, id) |> Repo.preload(marbles: :assets)

  ## Marbles
  def list_pack_marbles_by_rarity(pack_id, rarity) do
    from(m in Marble,
      join: p in assoc(m, :packs),
      where: p.id == ^pack_id and m.rarity == ^rarity,
      preload: [:assets, :team]
    )
    |> Repo.all()
  end

  def list_pack_marbles(pack_id) do
    from(m in Marble, where: m.pack_id == ^pack_id, preload: [:assets, :team])
    |> Repo.all()
  end

  def get_marble!(id), do: Repo.get!(Marble, id) |> Repo.preload([:assets, :team])

  def create_marble(attrs \\ %{}) do
    %Marble{}
    |> Marble.changeset(attrs)
    |> Repo.insert()
  end
end
