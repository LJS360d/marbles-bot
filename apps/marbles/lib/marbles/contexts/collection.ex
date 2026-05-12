defmodule Marbles.Collection do
  alias Marbles.{Accounts, AdminListing, Repo}
  alias Marbles.Schema.{UserMarble, Marble}
  import Ecto.Query

  @per_page 10

  @spec per_page() :: pos_integer()
  def per_page, do: @per_page

  @spec list_user_inventory(Ecto.UUID.t(), keyword()) :: {[UserMarble.t()], non_neg_integer()}
  def list_user_inventory(user_id, opts \\ []) do
    sort = Keyword.get(opts, :sort, :rarity_level_name)
    {_page, per, offset} = AdminListing.page_bounds(opts, @per_page)

    base =
      from(um in UserMarble,
        where: um.user_id == ^user_id,
        join: m in Marble,
        on: um.marble_id == m.id,
        preload: [marble: [:team, :assets, :abilities]]
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

  @spec acquire_marble_template(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:new, UserMarble.t()} | {:duplicate, pos_integer(), UserMarble.t()}
  def acquire_marble_template(user_id, marble_id, opts \\ [])
      when is_binary(user_id) and is_binary(marble_id) do
    meta = Keyword.get(opts, :meta, %{})
    marble = Repo.get!(Marble, marble_id)

    case Repo.get_by(UserMarble, user_id: user_id, marble_id: marble_id) do
      %UserMarble{} = existing ->
        duplicate_from_marble(user_id, marble, existing)

      nil ->
        case %UserMarble{}
             |> UserMarble.changeset(%{
               user_id: user_id,
               marble_id: marble_id,
               meta: meta
             })
             |> Repo.insert() do
          {:ok, um} ->
            {:new, um}

          {:error, _} ->
            existing = Repo.get_by!(UserMarble, user_id: user_id, marble_id: marble_id)
            duplicate_from_marble(user_id, marble, existing)
        end
    end
  end

  @spec duplicate_from_marble(Ecto.UUID.t(), Marble.t(), UserMarble.t()) ::
          {:duplicate, pos_integer(), UserMarble.t()}
  defp duplicate_from_marble(user_id, %Marble{} = marble, %UserMarble{} = existing) do
    dust = Marbles.Economy.Dust.amount_for_duplicate(marble.rarity || 1, user_id)
    {:ok, _} = Accounts.update_dust(Accounts.get_user!(user_id), dust)
    {:duplicate, dust, existing}
  end

  @spec add_marble_to_collection(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, UserMarble.t()} | {:error, Ecto.Changeset.t()}
  def add_marble_to_collection(user_id, marble_id, meta \\ %{}) do
    case acquire_marble_template(user_id, marble_id, meta: meta) do
      {:new, um} -> {:ok, um}
      {:duplicate, _dust, um} -> {:ok, um}
    end
  end

  @spec get_user_marble!(Ecto.UUID.t(), Ecto.UUID.t()) :: UserMarble.t()
  def get_user_marble!(user_id, user_marble_id) do
    Repo.get_by!(UserMarble, id: user_marble_id, user_id: user_id)
    |> Repo.preload(marble: [:team, :assets])
  end
end
