defmodule Marbles.Schema.CaughtSpawn do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:message_id, :string, autogenerate: false}
  @foreign_key_type :binary_id

  schema "caught_spawns" do
    belongs_to :user, Marbles.Schema.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(caught_spawn, attrs) do
    caught_spawn
    |> cast(attrs, [:message_id, :user_id])
    |> validate_required([:message_id, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
