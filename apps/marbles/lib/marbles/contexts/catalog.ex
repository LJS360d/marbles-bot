# Read-only operations
defmodule Marbles.Catalog do
  alias Marbles.Repo
  alias Marbles.Schema.{Team, Marble, Pack}
  import Ecto.Query

  ## Teams
  def list_teams, do: Repo.all(Team)

  def create_team(attrs \\ %{}) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  def update_team(%Team{} = team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update()
  end

  ## Packs
  def list_active_packs(as_of \\ Date.utc_today(), order \\ :name) do
    base =
      from(p in Pack,
        where: is_nil(p.start_date) or p.start_date <= ^as_of,
        where: is_nil(p.end_date) or p.end_date >= ^as_of,
        preload: [:marbles, :pull_rules]
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

  @marble_sort ~w(name edition role rarity team)a

  @spec list_marbles(keyword()) :: {[Marble.t()], non_neg_integer()}
  def list_marbles(opts \\ []) do
    page = Keyword.get(opts, :page, 1) |> max(1)
    per = Keyword.get(opts, :per_page, 25)
    offset = (page - 1) * per
    sort = normalize_marble_sort(Keyword.get(opts, :sort))
    order = normalize_marble_order(Keyword.get(opts, :order))
    q = Keyword.get(opts, :q, "") |> to_string() |> String.trim()

    base =
      from(m in Marble,
        as: :m,
        left_join: t in assoc(m, :team),
        as: :t,
        preload: [:team, :assets]
      )

    base = apply_marble_search(base, q)
    total = Repo.aggregate(base, :count, :id)
    ordered = apply_marble_order(base, sort, order)
    marbles = ordered |> offset(^offset) |> limit(^per) |> Repo.all()
    {marbles, total}
  end

  defp normalize_marble_sort(nil), do: :name

  defp normalize_marble_sort(s) when is_atom(s) do
    if s in @marble_sort, do: s, else: :name
  end

  defp normalize_marble_sort(s) when is_binary(s) do
    case s do
      "name" -> :name
      "edition" -> :edition
      "role" -> :role
      "rarity" -> :rarity
      "team" -> :team
      _ -> :name
    end
  end

  defp normalize_marble_order(nil), do: :asc
  defp normalize_marble_order(:asc), do: :asc
  defp normalize_marble_order("asc"), do: :asc
  defp normalize_marble_order(_), do: :desc

  defp apply_marble_search(query, ""), do: query

  defp apply_marble_search(query, q) do
    term = "%" <> (q |> admin_search_fragment() |> String.downcase()) <> "%"

    from([m, t] in query,
      where:
        fragment("LOWER(?) LIKE ?", m.name, ^term) or
          fragment("LOWER(?) LIKE ?", m.edition, ^term)
    )
  end

  defp admin_search_fragment(q) do
    q
    |> String.replace("\\", "")
    |> String.replace("%", "")
    |> String.replace("_", "")
  end

  defp apply_marble_order(query, :name, :asc), do: order_by(query, [m], asc: m.name)
  defp apply_marble_order(query, :name, :desc), do: order_by(query, [m], desc: m.name)
  defp apply_marble_order(query, :edition, :asc), do: order_by(query, [m], asc: m.edition)
  defp apply_marble_order(query, :edition, :desc), do: order_by(query, [m], desc: m.edition)
  defp apply_marble_order(query, :role, :asc), do: order_by(query, [m], asc: m.role)
  defp apply_marble_order(query, :role, :desc), do: order_by(query, [m], desc: m.role)
  defp apply_marble_order(query, :rarity, :asc), do: order_by(query, [m], asc: m.rarity)
  defp apply_marble_order(query, :rarity, :desc), do: order_by(query, [m], desc: m.rarity)

  defp apply_marble_order(query, :team, :asc),
    do: order_by(query, [m, t], asc_nulls_last: t.name)

  defp apply_marble_order(query, :team, :desc),
    do: order_by(query, [m, t], desc_nulls_last: t.name)

  def create_marble(attrs \\ %{}) do
    %Marble{}
    |> Marble.changeset(attrs)
    |> Repo.insert()
  end

  def update_marble(%Marble{} = marble, attrs) do
    marble
    |> Marble.changeset(attrs)
    |> Repo.update()
  end

  def list_all_packs(opts \\ []) do
    order = Keyword.get(opts, :order, :name)
    base = from(p in Pack, preload: [:marbles, :pull_rules])

    ordered =
      case order do
        :newest -> from(p in base, order_by: [desc: p.inserted_at])
        _ -> from(p in base, order_by: [asc: p.name])
      end

    Repo.all(ordered)
  end

  @pack_sort ~w(name cost inserted_at marble_count)a

  @spec list_packs(keyword()) :: {[%Pack{}], non_neg_integer()}
  def list_packs(opts \\ []) do
    page = Keyword.get(opts, :page, 1) |> max(1)
    per = Keyword.get(opts, :per_page, 25)
    offset = (page - 1) * per
    sort = normalize_pack_sort(Keyword.get(opts, :sort))
    order = normalize_pack_order(Keyword.get(opts, :order))
    q = Keyword.get(opts, :q, "") |> to_string() |> String.trim()

    base = from(p in Pack, as: :p, preload: [:marbles])
    base = apply_pack_search(base, q)
    total = Repo.aggregate(base, :count, :id)
    ordered = apply_pack_order(base, sort, order)
    packs = ordered |> offset(^offset) |> limit(^per) |> Repo.all()
    {packs, total}
  end

  defp normalize_pack_sort(nil), do: :name

  defp normalize_pack_sort(s) when is_atom(s) do
    if s in @pack_sort, do: s, else: :name
  end

  defp normalize_pack_sort(s) when is_binary(s) do
    case s do
      "name" -> :name
      "cost" -> :cost
      "inserted_at" -> :inserted_at
      "marble_count" -> :marble_count
      _ -> :name
    end
  end

  defp normalize_pack_order(nil), do: :asc
  defp normalize_pack_order(:asc), do: :asc
  defp normalize_pack_order("asc"), do: :asc
  defp normalize_pack_order(_), do: :desc

  defp apply_pack_search(query, ""), do: query

  defp apply_pack_search(query, q) do
    term = "%" <> (q |> admin_search_fragment() |> String.downcase()) <> "%"
    from(p in query, where: fragment("LOWER(?) LIKE ?", p.name, ^term))
  end

  defp apply_pack_order(query, :name, :asc), do: order_by(query, [p], asc: p.name)
  defp apply_pack_order(query, :name, :desc), do: order_by(query, [p], desc: p.name)
  defp apply_pack_order(query, :cost, :asc), do: order_by(query, [p], asc: p.cost)
  defp apply_pack_order(query, :cost, :desc), do: order_by(query, [p], desc: p.cost)
  defp apply_pack_order(query, :inserted_at, :asc), do: order_by(query, [p], asc: p.inserted_at)
  defp apply_pack_order(query, :inserted_at, :desc), do: order_by(query, [p], desc: p.inserted_at)

  defp apply_pack_order(query, :marble_count, :asc) do
    order_by(query, [p],
      asc: fragment("(SELECT COUNT(*)::int FROM pack_contents WHERE pack_id = ?)", p.id)
    )
  end

  defp apply_pack_order(query, :marble_count, :desc) do
    order_by(query, [p],
      desc: fragment("(SELECT COUNT(*)::int FROM pack_contents WHERE pack_id = ?)", p.id)
    )
  end
end
