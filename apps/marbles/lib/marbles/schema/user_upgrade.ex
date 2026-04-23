defmodule Marbles.Schema.UserUpgrade do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_upgrades" do
    field :upgrade_key, :string
    field :level, :integer, default: 0

    belongs_to :user, Marbles.Schema.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user_upgrade, attrs) do
    user_upgrade
    |> cast(attrs, [:user_id, :upgrade_key, :level])
    |> validate_required([:user_id, :upgrade_key, :level])
    |> validate_number(:level, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :upgrade_key])
  end
end
