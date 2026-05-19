defmodule Marbles.Economy.MineRoster do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.{Marble, UserMarble, UserSquad, UserSquadSlot}

  @max_slots 5

  @type autocomplete_choice :: %{
          name: String.t(),
          level: non_neg_integer(),
          rarity: non_neg_integer()
        }

  @type roster_entry :: %{
          name: String.t(),
          level: non_neg_integer(),
          rarity: pos_integer()
        }

  @spec view(Ecto.UUID.t()) :: {:ok, [roster_entry()]}
  def view(user_id) when is_binary(user_id) do
    case get_mine_squad(user_id) do
      nil ->
        {:ok, []}

      squad ->
        entries =
          Enum.map(squad.slots, fn slot ->
            um = slot.user_marble
            m = um.marble
            %{name: m.name, level: um.level || 1, rarity: m.rarity || 1}
          end)

        {:ok, entries}
    end
  end

  @spec list_assigned_user_marbles(Ecto.UUID.t()) :: [UserMarble.t()]
  def list_assigned_user_marbles(user_id) when is_binary(user_id) do
    case get_mine_squad(user_id) do
      nil ->
        []

      squad ->
        Enum.map(squad.slots, & &1.user_marble)
    end
  end

  @spec list_assigned_user_marble_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def list_assigned_user_marble_ids(user_id) when is_binary(user_id) do
    case get_mine_squad(user_id) do
      nil -> []
      squad -> Enum.map(squad.slots, & &1.user_marble_id)
    end
  end

  @spec add_by_marble_name(Ecto.UUID.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :roster_full | :already_in_roster | :invalid_name}
  def add_by_marble_name(user_id, name) when is_binary(name) do
    name = String.trim(name)

    if name == "" do
      {:error, :invalid_name}
    else
      um =
        from(um in UserMarble,
          join: m in Marble,
          on: m.id == um.marble_id,
          where: um.user_id == ^user_id,
          where: fragment("LOWER(?) = LOWER(?)", m.name, ^name),
          limit: 1
        )
        |> Repo.one()

      case um do
        nil -> {:error, :not_found}
        %{id: id} -> add_user_marble(user_id, id)
      end
    end
  end

  @spec remove_by_marble_name(Ecto.UUID.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :invalid_name}
  def remove_by_marble_name(user_id, name) when is_binary(name) do
    name = String.trim(name)

    if name == "" do
      {:error, :invalid_name}
    else
      ids = list_assigned_user_marble_ids(user_id)

      remove_id =
        from(um in UserMarble,
          join: m in Marble,
          on: m.id == um.marble_id,
          where: um.user_id == ^user_id and um.id in ^ids,
          where: fragment("LOWER(?) = LOWER(?)", m.name, ^name),
          select: um.id,
          limit: 1
        )
        |> Repo.one()

      case remove_id do
        nil -> {:error, :not_found}
        id -> remove_user_marble(user_id, id)
      end
    end
  end

  @spec add_user_marble(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, %{added: Ecto.UUID.t(), slots: pos_integer()}}
          | {:error, :not_found | :roster_full | :already_in_roster}
  def add_user_marble(user_id, user_marble_id)
      when is_binary(user_id) and is_binary(user_marble_id) do
    ids = list_assigned_user_marble_ids(user_id)

    cond do
      length(ids) >= @max_slots ->
        {:error, :roster_full}

      user_marble_id in ids ->
        {:error, :already_in_roster}

      Repo.get_by(UserMarble, id: user_marble_id, user_id: user_id) == nil ->
        {:error, :not_found}

      true ->
        squad = get_or_create_mine_squad(user_id)
        position = length(ids)

        %UserSquadSlot{}
        |> UserSquadSlot.mine_slot_changeset(%{
          squad_id: squad.id,
          user_marble_id: user_marble_id,
          position: position
        })
        |> Repo.insert!()

        {:ok, %{added: user_marble_id, slots: position + 1}}
    end
  end

  @spec remove_user_marble(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, %{removed: Ecto.UUID.t(), slots: non_neg_integer()}} | {:error, :not_found}
  def remove_user_marble(user_id, user_marble_id)
      when is_binary(user_id) and is_binary(user_marble_id) do
    case get_mine_squad(user_id) do
      nil ->
        {:error, :not_found}

      squad ->
        slot = Enum.find(squad.slots, &(&1.user_marble_id == user_marble_id))

        case slot do
          nil ->
            {:error, :not_found}

          %UserSquadSlot{} = s ->
            Repo.delete!(s)
            reindex_slots(squad.id)
            remaining = list_assigned_user_marble_ids(user_id)
            {:ok, %{removed: user_marble_id, slots: length(remaining)}}
        end
    end
  end

  @spec clear(Ecto.UUID.t()) :: {:ok, map()}
  def clear(user_id) when is_binary(user_id) do
    case get_mine_squad(user_id) do
      nil ->
        {:ok, %{slots: 0}}

      squad ->
        Repo.delete_all(from(s in UserSquadSlot, where: s.squad_id == ^squad.id))
        {:ok, %{slots: 0}}
    end
  end

  @spec autocomplete_owned(Ecto.UUID.t(), String.t()) :: [autocomplete_choice()]
  def autocomplete_owned(user_id, query \\ "") when is_binary(user_id) and is_binary(query) do
    roster_ids = list_assigned_user_marble_ids(user_id)
    q = String.downcase(String.trim(query))

    base =
      from(um in UserMarble,
        join: m in Marble,
        on: m.id == um.marble_id,
        where: um.user_id == ^user_id,
        where: um.id not in ^roster_ids,
        order_by: [asc: m.name, desc: um.level, desc: m.rarity],
        select: %{name: m.name, level: um.level, rarity: m.rarity}
      )

    rows =
      if q == "" do
        base
      else
        from([um, m] in base, where: fragment("LOWER(?) LIKE ?", m.name, ^"%#{q}%"))
      end

    rows
    |> Repo.all()
    |> uniq_by_name()
    |> Enum.take(25)
  end

  @spec autocomplete_roster(Ecto.UUID.t(), String.t()) :: [autocomplete_choice()]
  def autocomplete_roster(user_id, query \\ "") when is_binary(user_id) and is_binary(query) do
    ids = list_assigned_user_marble_ids(user_id)
    q = String.downcase(String.trim(query))

    if ids == [] do
      []
    else
      rows =
        from(um in UserMarble,
          join: m in Marble,
          on: m.id == um.marble_id,
          where: um.user_id == ^user_id and um.id in ^ids,
          select: {um.id, %{name: m.name, level: um.level, rarity: m.rarity}}
        )
        |> Repo.all()
        |> Map.new()

      ids
      |> Enum.map(&Map.get(rows, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn %{name: name} ->
        q == "" or String.contains?(String.downcase(name), q)
      end)
      |> uniq_by_name()
      |> Enum.take(25)
    end
  end

  # Returns mine squad with slots preloaded (ordered by position), or nil.
  @spec get_mine_squad(Ecto.UUID.t()) :: UserSquad.t() | nil
  def get_mine_squad(user_id) when is_binary(user_id) do
    slots_q =
      from(s in UserSquadSlot,
        order_by: [asc: s.position],
        preload: [user_marble: [marble: [:team, :abilities]]]
      )

    Repo.one(
      from(sq in UserSquad,
        where: sq.user_id == ^user_id and sq.purpose == :mine,
        preload: [slots: ^slots_q]
      )
    )
  end

  defp get_or_create_mine_squad(user_id) do
    case get_mine_squad(user_id) do
      %UserSquad{} = squad ->
        squad

      nil ->
        %UserSquad{}
        |> UserSquad.mine_changeset(%{user_id: user_id, name: "Mine Roster"})
        |> Repo.insert!()
    end
  end

  # After a removal, compact slot positions to 0..N-1 order.
  defp reindex_slots(squad_id) do
    slots =
      from(s in UserSquadSlot,
        where: s.squad_id == ^squad_id,
        order_by: [asc: s.position]
      )
      |> Repo.all()

    Enum.each(Enum.with_index(slots), fn {slot, idx} ->
      if slot.position != idx do
        Repo.update_all(
          from(s in UserSquadSlot, where: s.id == ^slot.id),
          set: [position: idx]
        )
      end
    end)
  end

  defp uniq_by_name(choices) do
    {acc, _seen} =
      Enum.reduce(choices, {[], MapSet.new()}, fn choice, {list, seen} ->
        if MapSet.member?(seen, choice.name) do
          {list, seen}
        else
          {[choice | list], MapSet.put(seen, choice.name)}
        end
      end)

    Enum.reverse(acc)
  end
end
