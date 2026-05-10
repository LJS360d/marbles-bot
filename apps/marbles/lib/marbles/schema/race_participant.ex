defmodule Marbles.Schema.RaceParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          race_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          squad_id: Ecto.UUID.t() | nil,
          final_position: integer() | nil,
          elo_before: integer() | nil,
          elo_after: integer() | nil,
          wage_coins: non_neg_integer(),
          payout_coins: non_neg_integer(),
          stats: map(),
          race: Ecto.Association.NotLoaded.t() | Marbles.Schema.RaceInstance.t() | nil,
          user: Ecto.Association.NotLoaded.t() | Marbles.Schema.User.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "race_participants" do
    field :final_position, :integer
    field :elo_before, :integer
    field :elo_after, :integer
    field :wage_coins, :integer, default: 0
    field :payout_coins, :integer, default: 0
    field :stats, :map, default: %{}

    belongs_to :race, Marbles.Schema.RaceInstance
    belongs_to :user, Marbles.Schema.User
    field :squad_id, :binary_id

    timestamps()
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(part, attrs) do
    part
    |> cast(attrs, [
      :race_id,
      :user_id,
      :squad_id,
      :final_position,
      :elo_before,
      :elo_after,
      :wage_coins,
      :payout_coins,
      :stats
    ])
    |> validate_required([:race_id, :user_id])
    |> validate_number(:wage_coins, greater_than_or_equal_to: 0)
    |> validate_number(:payout_coins, greater_than_or_equal_to: 0)
    |> unique_constraint([:race_id, :user_id],
      name: :race_participants_race_id_user_id_index
    )
  end
end
