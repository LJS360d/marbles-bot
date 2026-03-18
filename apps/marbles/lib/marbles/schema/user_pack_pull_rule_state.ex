defmodule Marbles.Schema.UserPackPullRuleState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "user_pack_pull_rule_states" do
    field :uses_consumed, :integer, default: 0
    field :period_bucket, :string
    field :pulls_accumulated, :integer, default: 0

    belongs_to :user, Marbles.Schema.User, type: :binary_id
    belongs_to :rule, Marbles.Schema.PackPullRule, type: :binary_id, foreign_key: :rule_id

    timestamps()
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:user_id, :rule_id, :uses_consumed, :period_bucket, :pulls_accumulated])
    |> validate_required([:user_id, :rule_id])
    |> validate_number(:uses_consumed, greater_than_or_equal_to: 0)
    |> validate_number(:pulls_accumulated, greater_than_or_equal_to: 0)
  end
end
