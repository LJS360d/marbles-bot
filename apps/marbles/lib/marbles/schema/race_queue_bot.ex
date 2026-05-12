defmodule Marbles.Schema.RaceQueueBot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          label: String.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          squad_id: Ecto.UUID.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "race_queue_bots" do
    field :label, :string
    belongs_to :user, Marbles.Schema.User
    belongs_to :squad, Marbles.Schema.UserSquad

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(bot, attrs) do
    bot
    |> cast(attrs, [:user_id, :squad_id, :label])
    |> validate_required([:user_id, :squad_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:squad_id)
    |> unique_constraint(:user_id)
  end
end
