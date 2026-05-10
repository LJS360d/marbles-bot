defmodule Marbles.Racing.Engine.State do
  @moduledoc false

  alias Marbles.Racing.Engine.Setup

  @type t :: %__MODULE__{}

  defstruct [
    :race_id,
    :race_type,
    :event_id,
    :pool_id,
    :parent_pid,
    :rng,
    :track,
    :weather,
    :config,
    :seed,
    :started_at,
    :finished_at,
    pot_coins: 0,
    live_contribs: %{},
    t: 0.0,
    tick_index: 0,
    last_coach_pulse: 0.0,
    marbles: [],
    coaches: %{},
    squads: %{},
    participants: [],
    replay_frames: [],
    pending_frames: []
  ]

  @spec from_setup(Setup.t(), map()) :: t()
  def from_setup(%Setup{} = setup, config) do
    rng = :rand.seed_s(:exsss, {setup.seed, 0, 0})
    pot = Enum.reduce(setup.participants, 0, fn p, acc -> acc + p.wage end)

    {marbles, coaches, squads, _rng} = build_marbles(setup, rng)

    %__MODULE__{
      race_id: setup.race_id,
      race_type: setup.race_type,
      event_id: setup.event_id,
      pool_id: setup.pool_id,
      parent_pid: setup.parent_pid,
      rng: rng,
      track: setup.track,
      weather: setup.weather,
      config: config,
      seed: setup.seed,
      started_at: DateTime.utc_now(),
      pot_coins: pot,
      marbles: marbles,
      coaches: coaches,
      squads: squads,
      participants: setup.participants
    }
  end

  defp build_marbles(setup, rng) do
    {marbles, rng} =
      Enum.flat_map_reduce(setup.participants, rng, fn p, rng_in ->
        Enum.map_reduce(p.racers, rng_in, fn racer, rng_acc ->
          {jitter, rng_next} = :rand.uniform_s(rng_acc)
          marble = build_marble(racer, p.user_id, (jitter - 0.5) * 0.6)
          {marble, rng_next}
        end)
      end)

    coaches =
      setup.participants
      |> Enum.map(fn p -> {p.user_id, build_coach(p.coach, p.user_id)} end)
      |> Map.new()

    squads =
      setup.participants
      |> Enum.map(fn p ->
        {p.user_id,
         %{
           racers: p.racers,
           coach: p.coach,
           elo: p.elo,
           wage: p.wage
         }}
      end)
      |> Map.new()

    {marbles, coaches, squads, rng}
  end

  defp build_marble(racer, user_id, jitter_x) do
    %{
      id: racer.user_marble_id || racer.marble_id,
      marble_id: racer.marble_id,
      user_marble_id: racer[:user_marble_id],
      user_id: user_id,
      name: racer.name,
      rarity: racer.rarity,
      team_id: racer.team_id,
      texture_path: racer[:texture_path],
      base_stats: racer.base_stats,
      ability_keys: racer.ability_keys || [],
      modifiers: %{},
      stamina: racer.base_stats.stamina,
      velocity: 0.0,
      position: 0.0,
      x_anchor: jitter_x,
      y_anchor: 0.0,
      rank: 0,
      status: :running,
      finished_at: nil,
      __final_stretched: false,
      __coach_buff_until: 0.0,
      __strategist_until: 0.0
    }
  end

  defp build_coach(nil, _user_id), do: nil

  defp build_coach(coach, user_id) do
    %{
      id: coach.user_marble_id || coach.marble_id,
      marble_id: coach.marble_id,
      user_id: user_id,
      name: coach.name,
      rarity: coach.rarity,
      team_id: coach.team_id,
      base_stats: coach.base_stats,
      ability_keys: coach.ability_keys || [],
      modifiers: %{}
    }
  end

  @spec public_setup(t()) :: map()
  def public_setup(%__MODULE__{} = state) do
    %{
      race_id: state.race_id,
      race_type: state.race_type,
      event_id: state.event_id,
      seed: state.seed,
      track: state.track,
      weather: state.weather,
      pot_coins: state.pot_coins,
      participants:
        Enum.map(state.participants, fn p ->
          %{
            user_id: p.user_id,
            squad_id: p.squad_id,
            elo: p.elo,
            wage: p.wage,
            racers: Enum.map(p.racers, &public_marble/1),
            coach: if(p.coach, do: public_marble(p.coach), else: nil)
          }
        end)
    }
  end

  defp public_marble(m) do
    %{
      marble_id: m.marble_id,
      user_marble_id: m[:user_marble_id],
      name: m.name,
      rarity: m.rarity,
      team_id: m.team_id,
      texture_path: m[:texture_path],
      ability_keys: Enum.map(m.ability_keys || [], &Atom.to_string/1)
    }
  end

  @spec summary(t()) :: %{
          race_id: Ecto.UUID.t(),
          finished_at: DateTime.t() | nil,
          duration: float(),
          finishers: [map()]
        }
  def summary(%__MODULE__{} = state) do
    finishers =
      state.marbles
      |> Enum.sort_by(&{&1.rank})
      |> Enum.map(fn m ->
        %{
          marble_id: m.marble_id,
          user_marble_id: m[:user_marble_id],
          user_id: m.user_id,
          rank: m.rank,
          finished_at: m.finished_at
        }
      end)

    %{
      race_id: state.race_id,
      finished_at: state.finished_at,
      duration: state.t,
      finishers: finishers
    }
  end
end
