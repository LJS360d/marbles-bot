defmodule Marbles.Plinko do
  @moduledoc """
  Plinko reward roll for the daily claim.

  Seven slots, all multipliers >= 1.0x. Center slot yields the best reward.
  Slot distribution follows a normal distribution (Box-Muller) centered at
  the middle slot, matching the physical Galton board probability of the 3D scene.
  """

  alias Marbles.Repo
  alias Marbles.Schema.{UserMarble, Marble}
  import Ecto.Query

  @num_rows 6
  @num_slots 7
  @center_slot div(@num_slots - 1, 2)

  # All multipliers >= 1.0 — plinko never penalizes, only rewards.
  # Symmetric around center, center is highest.
  @slots [
    %{id: 0, label: "1.0×", coin_mult: 1.0, xp_mult: 1.0},
    %{id: 1, label: "1.2×", coin_mult: 1.2, xp_mult: 1.0},
    %{id: 2, label: "1.5×", coin_mult: 1.5, xp_mult: 1.1},
    %{id: 3, label: "2.5×", coin_mult: 2.5, xp_mult: 1.25},
    %{id: 4, label: "1.5×", coin_mult: 1.5, xp_mult: 1.1},
    %{id: 5, label: "1.2×", coin_mult: 1.2, xp_mult: 1.0},
    %{id: 6, label: "1.0×", coin_mult: 1.0, xp_mult: 1.0}
  ]

  @type slot :: %{
          id: non_neg_integer(),
          label: String.t(),
          coin_mult: float(),
          xp_mult: float()
        }

  @type roll_result :: %{
          slot: slot(),
          marble: map() | nil
        }

  @spec slots() :: [slot()]
  def slots, do: @slots

  @spec num_rows() :: non_neg_integer()
  def num_rows, do: @num_rows

  @spec num_slots() :: non_neg_integer()
  def num_slots, do: @num_slots

  @doc """
  Samples a plinko result. Picks a random slot via normal distribution and
  optionally fetches a random marble from the user's collection for the visual.

  Returns `%{slot: slot, marble: user_marble_or_nil}`.
  """
  @spec roll(Ecto.UUID.t() | nil) :: roll_result()
  def roll(user_id \\ nil) do
    slot = sample_slot()
    marble = if user_id, do: pick_marble(user_id), else: nil
    %{slot: slot, marble: marble}
  end

  @spec sample_slot() :: slot()
  defp sample_slot do
    # std_dev ~1.4 keeps ~85% of mass in the three central slots
    std_dev = 1.4
    u1 = max(:rand.uniform(), 1.0e-10)
    u2 = :rand.uniform()
    z = :math.sqrt(-2.0 * :math.log(u1)) * :math.cos(2.0 * :math.pi() * u2)
    idx = (@center_slot + z * std_dev) |> round() |> max(0) |> min(@num_slots - 1)
    Enum.at(@slots, idx)
  end

  @spec pick_marble(Ecto.UUID.t()) :: map() | nil
  defp pick_marble(user_id) do
    Repo.one(
      from(um in UserMarble,
        where: um.user_id == ^user_id,
        join: m in Marble,
        on: um.marble_id == m.id,
        order_by: fragment("RANDOM()"),
        limit: 1,
        preload: [marble: :assets]
      )
    )
  end
end
