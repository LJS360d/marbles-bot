defmodule Marbles.Racing.Events.Eligibility do
  @moduledoc """
  Pure functions to check whether a (user, squad) pair is eligible for an
  event given its `config` rules.
  """

  alias Marbles.Repo
  alias Marbles.Schema.{UserRaceStat, UserSquad}

  @spec check(Marbles.Schema.Event.t(), Ecto.UUID.t(), UserSquad.t()) ::
          :ok | {:error, :ineligible}
  def check(event, user_id, %UserSquad{} = squad) do
    cfg = event.config || %{}
    elo = fetch_elo(user_id)

    if check_elo(cfg, elo) and check_min_level(cfg, squad) and check_team_rules(cfg, squad) do
      :ok
    else
      {:error, :ineligible}
    end
  end

  defp fetch_elo(user_id) do
    case Repo.get_by(UserRaceStat, user_id: user_id) do
      %UserRaceStat{elo: elo} -> elo
      nil -> 1000
    end
  end

  defp check_elo(cfg, elo) do
    elo_min = Map.get(cfg, "elo_min", 0)
    elo_max = Map.get(cfg, "elo_max", 9_999)
    elo >= elo_min and elo <= elo_max
  end

  defp check_min_level(cfg, %UserSquad{slots: slots}) when is_list(slots) do
    minimum = Map.get(cfg, "min_marble_level", 1)
    Enum.all?(slots, fn s -> ((s.user_marble && s.user_marble.level) || 1) >= minimum end)
  end

  defp check_min_level(_cfg, _squad), do: true

  defp check_team_rules(cfg, %UserSquad{slots: slots}) when is_list(slots) do
    whitelist = Map.get(cfg, "team_whitelist", []) |> MapSet.new()
    blacklist = Map.get(cfg, "team_blacklist", []) |> MapSet.new()

    team_ids =
      slots
      |> Enum.map(fn s ->
        s.user_marble && s.user_marble.marble && s.user_marble.marble.team_id
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    no_blacklisted? = Enum.all?(team_ids, fn t -> not MapSet.member?(blacklist, t) end)

    whitelist_ok? =
      if MapSet.size(whitelist) == 0,
        do: true,
        else: Enum.any?(team_ids, fn t -> MapSet.member?(whitelist, t) end)

    no_blacklisted? and whitelist_ok?
  end

  defp check_team_rules(_cfg, _squad), do: true
end
