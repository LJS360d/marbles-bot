defmodule Marbles.Schema.UserEffect do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_effects" do
    field :effect_key, :string
    field :scope, :string, default: "account"
    field :guild_id, :string
    field :expires_at, :utc_datetime_usec
    field :meta, :map, default: %{}

    belongs_to :user, Marbles.Schema.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user_effect, attrs) do
    user_effect
    |> cast(attrs, [:user_id, :effect_key, :scope, :guild_id, :expires_at, :meta])
    |> validate_required([:user_id, :effect_key, :scope, :expires_at])
  end
end
