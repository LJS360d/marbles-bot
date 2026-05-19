defmodule Marbles.Racing.Squads do
  @moduledoc """
  Squad CRUD and validation.

  A squad is a named roster: 3 racer slots + 1 coach slot, drawn from a
  user's `UserMarble` collection. Each user has a soft cap of squad slots
  determined by `Marbles.Schema.UserSquadUnlock.max_slots` (default 3 on unlock).
  """

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Schema.{Marble, UserMarble, UserSquad, UserSquadSlot, UserSquadUnlock}

  @racer_roles UserSquadSlot.racer_roles()

  @type slot_role :: UserSquadSlot.role()

  @spec ensure_unlock(Ecto.UUID.t()) :: UserSquadUnlock.t()
  def ensure_unlock(user_id) do
    case Repo.get_by(UserSquadUnlock, user_id: user_id) do
      %UserSquadUnlock{} = u ->
        u

      nil ->
        %UserSquadUnlock{}
        |> UserSquadUnlock.changeset(%{user_id: user_id, max_slots: 3})
        |> Repo.insert!()
    end
  end

  @spec set_max_slots(Ecto.UUID.t(), pos_integer()) ::
          {:ok, UserSquadUnlock.t()} | {:error, Ecto.Changeset.t()}
  def set_max_slots(user_id, max_slots) when is_integer(max_slots) and max_slots > 0 do
    ensure_unlock(user_id)
    |> UserSquadUnlock.changeset(%{max_slots: max_slots})
    |> Repo.update()
  end

  @spec list_user_squads(Ecto.UUID.t()) :: [UserSquad.t()]
  def list_user_squads(user_id) do
    from(s in UserSquad,
      where: s.user_id == ^user_id and s.purpose == :race,
      order_by: [asc: s.slot_index],
      preload: [slots: ^slots_preload()]
    )
    |> Repo.all()
  end

  defp slots_preload do
    from(s in UserSquadSlot,
      preload: [user_marble: [marble: [:team, :abilities]]]
    )
  end

  @spec get_user_squad(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, UserSquad.t()} | {:error, :not_found}
  def get_user_squad(user_id, squad_id) do
    case Repo.one(
           from(s in UserSquad,
             where: s.user_id == ^user_id and s.id == ^squad_id,
             preload: [slots: ^slots_preload()]
           )
         ) do
      nil -> {:error, :not_found}
      squad -> {:ok, squad}
    end
  end

  @doc """
  Create or update a squad in a slot index, replacing its members in one
  transaction.

  `members` is a map of `%{role => user_marble_id}`. Roles whose value is
  `nil` (or which are absent) are simply omitted — squads can be partial:
  at minimum one racer slot must be populated; coach is optional.
  """
  @spec upsert(Ecto.UUID.t(), pos_integer(), String.t(), %{
          optional(slot_role()) => Ecto.UUID.t() | nil
        }) ::
          {:ok, UserSquad.t()} | {:error, atom() | Ecto.Changeset.t()}
  def upsert(user_id, slot_index, name, members) do
    members = drop_empty_members(members)

    with :ok <- validate_member_keys(members),
         :ok <- validate_at_least_one_racer(members),
         :ok <- validate_max_slots(user_id, slot_index),
         :ok <- validate_member_ownership(user_id, members),
         :ok <- validate_distinct_marbles(members),
         :ok <- validate_coach_slot(members) do
      Repo.transaction(fn ->
        squad =
          case Repo.get_by(UserSquad, user_id: user_id, slot_index: slot_index) do
            %UserSquad{} = existing ->
              existing
              |> UserSquad.changeset(%{name: name})
              |> Repo.update!()

            nil ->
              %UserSquad{}
              |> UserSquad.changeset(%{
                user_id: user_id,
                slot_index: slot_index,
                name: name
              })
              |> Repo.insert!()
          end

        Repo.delete_all(from(s in UserSquadSlot, where: s.squad_id == ^squad.id))

        Enum.each(members, fn {role, user_marble_id} ->
          %UserSquadSlot{}
          |> UserSquadSlot.changeset(%{
            squad_id: squad.id,
            role: role,
            user_marble_id: user_marble_id
          })
          |> Repo.insert!()
        end)

        Repo.preload(squad, slots: slots_preload())
      end)
    end
  end

  defp drop_empty_members(members) when is_map(members) do
    members
    |> Enum.reject(fn {_role, id} -> is_nil(id) or id == "" end)
    |> Map.new()
  end

  defp drop_empty_members(_), do: %{}

  @spec delete(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def delete(user_id, squad_id) do
    case Repo.get_by(UserSquad, user_id: user_id, id: squad_id) do
      nil ->
        {:error, :not_found}

      squad ->
        Repo.delete!(squad)
        :ok
    end
  end

  @spec validate_member_keys(map()) :: :ok | {:error, :invalid_role}
  defp validate_member_keys(members) do
    allowed = MapSet.new(UserSquadSlot.roles())

    if Enum.all?(Map.keys(members), &MapSet.member?(allowed, &1)) do
      :ok
    else
      {:error, :invalid_role}
    end
  end

  @spec validate_at_least_one_racer(map()) :: :ok | {:error, :empty_squad}
  defp validate_at_least_one_racer(members) do
    racers = UserSquadSlot.racer_roles()

    if Enum.any?(racers, fn r -> Map.has_key?(members, r) end) do
      :ok
    else
      {:error, :empty_squad}
    end
  end

  @spec validate_max_slots(Ecto.UUID.t(), non_neg_integer()) ::
          :ok | {:error, :slot_locked}
  defp validate_max_slots(user_id, slot_index) do
    %UserSquadUnlock{max_slots: max} = ensure_unlock(user_id)
    if slot_index < max, do: :ok, else: {:error, :slot_locked}
  end

  @spec validate_member_ownership(Ecto.UUID.t(), map()) ::
          :ok | {:error, :not_owner}
  defp validate_member_ownership(_user_id, members) when map_size(members) == 0, do: :ok

  defp validate_member_ownership(user_id, members) do
    ids = members |> Map.values() |> Enum.uniq()

    owned =
      from(um in UserMarble,
        where: um.user_id == ^user_id and um.id in ^ids,
        select: um.id
      )
      |> Repo.all()
      |> MapSet.new()

    if MapSet.equal?(owned, MapSet.new(ids)), do: :ok, else: {:error, :not_owner}
  end

  defp validate_distinct_marbles(members) do
    values = Map.values(members)
    if length(values) == length(Enum.uniq(values)), do: :ok, else: {:error, :duplicate_marbles}
  end

  @spec validate_coach_slot(map()) :: :ok | {:error, :invalid_coach}
  defp validate_coach_slot(%{coach: user_marble_id}) when not is_nil(user_marble_id) do
    case Repo.one(
           from(um in UserMarble,
             where: um.id == ^user_marble_id,
             join: m in Marble,
             on: m.id == um.marble_id,
             select: %{role: m.role, meta: um.meta}
           )
         ) do
      %{role: :coach} ->
        :ok

      %{meta: meta} when is_map(meta) ->
        if Map.get(meta, "coach_eligible") == true, do: :ok, else: {:error, :invalid_coach}

      _ ->
        {:error, :invalid_coach}
    end
  end

  defp validate_coach_slot(_), do: :ok

  @doc """
  Computes a static digest of a squad: the present racers, the coach (or
  `nil`), and the team-id list used by the team-signature ability.

  Empty roles are skipped — squads can be partial (1..3 racers, optional
  coach).
  """
  @spec digest(UserSquad.t()) :: %{
          squad_id: Ecto.UUID.t() | nil,
          racers: [map()],
          coach: map() | nil,
          team_ids: [Ecto.UUID.t() | nil]
        }
  def digest(%UserSquad{slots: slots}) do
    by_role = Map.new(slots, fn s -> {s.role, s} end)

    racers =
      @racer_roles
      |> Enum.map(&slot_to_racer(by_role[&1]))
      |> Enum.reject(&is_nil/1)

    coach = slot_to_racer(by_role[:coach])
    coach_team = coach && coach.team_id

    %{
      squad_id: nil,
      racers: racers,
      coach: coach,
      team_ids: Enum.map(racers, & &1.team_id) ++ List.wrap(coach_team)
    }
  end

  defp slot_to_racer(nil), do: nil

  defp slot_to_racer(%UserSquadSlot{user_marble: %UserMarble{} = um}) do
    marble = um.marble

    %{
      user_marble_id: um.id,
      marble_id: marble.id,
      name: marble.name,
      rarity: marble.rarity,
      team_id: marble.team_id,
      texture_path: marble.texture_path,
      base_stats: stat_map(marble.base_stats || %{}),
      level: um.level,
      ability_keys: ability_keys(marble.abilities)
    }
  end

  defp ability_keys(nil), do: []
  defp ability_keys(%Ecto.Association.NotLoaded{}), do: []

  defp ability_keys(list) when is_list(list) do
    list
    |> Enum.map(fn %Marbles.Schema.MarbleAbility{ability_key: k} -> safe_atom(k) end)
    |> Enum.reject(&is_nil/1)
  end

  defp safe_atom(nil), do: nil

  defp safe_atom(k) when is_binary(k) do
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> nil
    end
  end

  defp safe_atom(k) when is_atom(k), do: k

  @spec stat_map(map()) :: %{
          top_speed: float(),
          acceleration: float(),
          stamina: float(),
          control: float(),
          weight: float()
        }
  def stat_map(stats) when is_map(stats) do
    %{
      top_speed: float_stat(stats, "top_speed", 1.0),
      acceleration: float_stat(stats, "acceleration", 1.0),
      stamina: float_stat(stats, "stamina", 1.0),
      control: float_stat(stats, "control", 1.0),
      weight: float_stat(stats, "weight", 1.0)
    }
  end

  defp float_stat(stats, key, default) do
    case Map.get(stats, key, Map.get(stats, String.to_atom(key), default)) do
      n when is_number(n) -> n / 1
      _ -> default
    end
  rescue
    ArgumentError -> default
  end
end
