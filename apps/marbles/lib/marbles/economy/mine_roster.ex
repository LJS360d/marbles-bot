defmodule Marbles.Economy.MineRoster do
  @moduledoc false

  import Ecto.Query
  alias Marbles.Repo
  alias Marbles.Schema.{User, UserMarble, Marble}
  alias Marbles.Accounts

  @max_slots 5
  @type autocomplete_choice :: %{
          name: String.t(),
          level: non_neg_integer(),
          rarity: non_neg_integer()
        }

  @spec view(Ecto.UUID.t()) :: {:ok, [String.t()]} | {:error, term()}
  def view(user_id) do
    user = Repo.get(User, user_id)
    if user, do: {:ok, describe_roster(user_id, user.mine_roster)}, else: {:error, :not_found}
  end

  defp describe_roster(user_id, roster) do
    ids = slot_ids(roster)

    names =
      if ids == [] do
        []
      else
        from(um in UserMarble,
          join: m in Marble,
          on: m.id == um.marble_id,
          where: um.user_id == ^user_id and um.id in ^ids,
          select: {um.id, m.name}
        )
        |> Repo.all()
        |> Map.new()
      end

    Enum.map(ids, fn id -> Map.get(names, id, "(missing)") end)
  end

  @spec add_by_marble_name(Ecto.UUID.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :roster_full | :already_in_roster | :invalid_name}
  def add_by_marble_name(user_id, name) when is_binary(name) do
    name = String.trim(name)

    if name == "" do
      {:error, :invalid_name}
    else
      user = Repo.get!(User, user_id)
      ids = slot_ids(user.mine_roster)

      if length(ids) >= @max_slots do
        {:error, :roster_full}
      else
        um =
          from(um in UserMarble,
            join: m in Marble,
            on: m.id == um.marble_id,
            where: um.user_id == ^user_id,
            where: fragment("LOWER(?) = LOWER(?)", m.name, ^name),
            select: um,
            limit: 1
          )
          |> Repo.one()

        case um do
          nil ->
            {:error, :not_found}

          %{id: id} ->
            if id in ids do
              {:error, :already_in_roster}
            else
              new_roster = %{"slots" => ids ++ [id]}
              {:ok, _} = Accounts.update_user(user, %{mine_roster: new_roster})
              {:ok, %{added: id, slots: length(ids) + 1}}
            end
        end
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
      user = Repo.get!(User, user_id)
      ids = slot_ids(user.mine_roster)

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
        nil ->
          {:error, :not_found}

        id ->
          new_ids = Enum.reject(ids, &(&1 == id))
          {:ok, _} = Accounts.update_user(user, %{mine_roster: %{"slots" => new_ids}})
          {:ok, %{removed: id, slots: length(new_ids)}}
      end
    end
  end

  @spec clear(Ecto.UUID.t()) :: {:ok, map()}
  def clear(user_id) do
    user = Repo.get!(User, user_id)
    {:ok, _} = Accounts.update_user(user, %{mine_roster: %{"slots" => []}})
    {:ok, %{slots: 0}}
  end

  @spec autocomplete_owned(Ecto.UUID.t(), String.t()) :: [autocomplete_choice()]
  def autocomplete_owned(user_id, query \\ "") when is_binary(user_id) and is_binary(query) do
    user = Repo.get!(User, user_id)
    roster_ids = slot_ids(user.mine_roster)
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
    |> uniq_autocomplete_choices_by_name()
    |> Enum.take(25)
  end

  @spec autocomplete_roster(Ecto.UUID.t(), String.t()) :: [autocomplete_choice()]
  def autocomplete_roster(user_id, query \\ "") when is_binary(user_id) and is_binary(query) do
    user = Repo.get!(User, user_id)
    ids = slot_ids(user.mine_roster)
    q = String.downcase(String.trim(query))

    if ids == [] do
      []
    else
      roster_rows =
        from(um in UserMarble,
          join: m in Marble,
          on: m.id == um.marble_id,
          where: um.user_id == ^user_id and um.id in ^ids,
          select: {um.id, %{name: m.name, level: um.level, rarity: m.rarity}}
        )
        |> Repo.all()
        |> Map.new()

      ids
      |> Enum.map(&Map.get(roster_rows, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn %{name: name} ->
        q == "" || String.contains?(String.downcase(name), q)
      end)
      |> uniq_autocomplete_choices_by_name()
      |> Enum.take(25)
    end
  end

  defp uniq_autocomplete_choices_by_name(choices) do
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

  defp slot_ids(roster) do
    roster = roster || %{}
    raw = Map.get(roster, "slots") || Map.get(roster, :slots) || []

    raw
    |> List.wrap()
    |> Enum.filter(fn id ->
      match?({:ok, _}, Ecto.UUID.cast(to_string(id)))
    end)
    |> Enum.map(&to_string/1)
    |> Enum.take(@max_slots)
  end
end
