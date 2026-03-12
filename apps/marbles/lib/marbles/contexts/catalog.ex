# Read-only operations
defmodule Marbles.Catalog do
  alias Marbles.Repo
  alias Marbles.Schema.{Team, Marble, Pack}
  import Ecto.Query

  ## Teams
  def list_teams, do: Repo.all(Team)

  ## Packs
  def list_active_packs(as_of \\ Date.utc_today(), order \\ :name) do
    base =
      from(p in Pack,
        where: p.active == true,
        where: is_nil(p.start_date) or p.start_date <= ^as_of,
        where: is_nil(p.end_date) or p.end_date >= ^as_of,
        preload: [:marbles]
      )

    ordered =
      case order do
        :newest -> from(p in base, order_by: [desc: p.inserted_at])
        _ -> from(p in base, order_by: [asc: p.name])
      end

    Repo.all(ordered)
  end

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
    from(m in Marble,
      join: p in assoc(m, :packs),
      where: p.id == ^pack_id,
      preload: [:assets, :team]
    )
    |> Repo.all()
  end

  def list_marbles_in_active_packs do
    list_active_packs()
    |> Enum.flat_map(fn pack -> pack.marbles || [] end)
    |> Enum.uniq_by(& &1.id)
  end

  def get_marble!(id), do: Repo.get!(Marble, id) |> Repo.preload([:assets, :team])

  def create_marble(attrs \\ %{}) do
    %Marble{}
    |> Marble.changeset(attrs)
    |> Repo.insert()
  end
end
