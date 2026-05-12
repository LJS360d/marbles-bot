defmodule Marbles.Racing.Queue.BotFill do
  @moduledoc """
  Configuration and bot-account loading for low-ELO queue fill.

  Injection timing and bracket rules live in `Marbles.Racing.Queue` so the
  GenServer stays the single orchestrator. Add a custom strategy module here
  later if you need richer bot selection.

  `low_elo_max_bucket` is **inclusive** and matches the queue’s
  `bracket = div(elo, bracket_step)`. With the default step of 100, ELO 1000
  is bucket **10** — if `low_elo_max_bucket` is below that, bots never join
  the starter bracket.
  """

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Schema.RaceQueueBot

  @type bot_account :: %{user_id: Ecto.UUID.t(), squad_id: Ecto.UUID.t(), label: String.t() | nil}

  @spec config() :: %{
          enabled: boolean(),
          interval_ms: pos_integer(),
          low_elo_max_bucket: integer(),
          target_party: pos_integer()
        }
  def config do
    defaults = [
      enabled: true,
      interval_ms: 120_000,
      low_elo_max_bucket: 20,
      target_party: 4
    ]

    defaults
    |> Keyword.merge(Application.get_env(:marbles, __MODULE__, []) || [])
    |> Map.new()
  end

  @spec load_accounts() :: [bot_account()]
  def load_accounts do
    q = from(b in RaceQueueBot, select: {b.user_id, b.squad_id, b.label})

    try do
      q
      |> Repo.all()
      |> Enum.map(fn {uid, sid, label} ->
        %{user_id: uid, squad_id: sid, label: label}
      end)
    rescue
      e ->
        msg = Exception.message(e)

        if String.contains?(msg, "race_queue_bots") and String.contains?(msg, "no such table") do
          []
        else
          reraise(e, __STACKTRACE__)
        end
    end
  end
end
