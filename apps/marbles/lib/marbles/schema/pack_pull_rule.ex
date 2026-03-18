defmodule Marbles.Schema.PackPullRule do
  use Ecto.Schema
  import Ecto.Changeset

  @effect_types ~w(discount pity)
  @trigger_types ~w(always lifetime_uses period_once every_n_pulls)
  @period_units ~w(day week month)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "pack_pull_rules" do
    field :effect_type, :string
    field :discount_percent, :integer, default: 0
    field :min_rarity, :integer
    field :apply_1x, :boolean, default: true
    field :apply_10x, :boolean, default: true
    field :trigger_type, :string
    field :lifetime_max_uses, :integer
    field :period_unit, :string
    field :every_n_pulls, :integer
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec

    belongs_to :pack, Marbles.Schema.Pack, type: :binary_id
    has_many :user_states, Marbles.Schema.UserPackPullRuleState, foreign_key: :rule_id

    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :pack_id,
      :effect_type,
      :discount_percent,
      :min_rarity,
      :apply_1x,
      :apply_10x,
      :trigger_type,
      :lifetime_max_uses,
      :period_unit,
      :every_n_pulls,
      :starts_at,
      :ends_at
    ])
    |> validate_required([:pack_id, :effect_type, :trigger_type])
    |> validate_inclusion(:effect_type, @effect_types)
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> validate_number(:discount_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_min_rarity_if_pity()
    |> validate_trigger_fields()
    |> validate_discount_scope()
    |> validate_pity_shape()
  end

  defp validate_discount_scope(cs) do
    if get_field(cs, :effect_type) == "discount" do
      if get_field(cs, :apply_1x) == false and get_field(cs, :apply_10x) == false do
        add_error(cs, :apply_1x, "select at least 1× or 10×")
      else
        cs
      end
    else
      put_change(cs, :apply_1x, true)
      |> put_change(:apply_10x, true)
    end
  end

  defp validate_pity_shape(cs) do
    if get_field(cs, :effect_type) == "pity" do
      if get_field(cs, :trigger_type) != "every_n_pulls" do
        add_error(cs, :trigger_type, "pity uses marble streak only (set N below)")
      else
        cs
      end
    else
      cs
    end
  end

  defp validate_trigger_fields(changeset) do
    changeset
    |> validate_required_by_trigger()
    |> clear_irrelevant_fields()
  end

  defp validate_required_by_trigger(cs) do
    t = get_field(cs, :trigger_type)
    e = get_field(cs, :effect_type)

    cs =
      case t do
        "lifetime_uses" ->
          validate_required(cs, [:lifetime_max_uses])

        "period_once" ->
          validate_required(cs, [:period_unit])
          |> validate_inclusion(:period_unit, @period_units)

        "every_n_pulls" ->
          validate_required(cs, [:every_n_pulls])
          |> validate_number(:every_n_pulls, greater_than: 0)

        _ ->
          cs
      end

    cs =
      if e == "pity" do
        validate_required(cs, [:min_rarity])
      else
        put_change(cs, :min_rarity, nil)
      end

    cs
  end

  defp validate_min_rarity_if_pity(cs) do
    if get_field(cs, :effect_type) == "pity" do
      validate_number(cs, :min_rarity, greater_than_or_equal_to: 1, less_than_or_equal_to: 3)
    else
      cs
    end
  end

  defp clear_irrelevant_fields(cs) do
    t = get_field(cs, :trigger_type)
    e = get_field(cs, :effect_type)

    cs =
      cond do
        t != "lifetime_uses" -> put_change(cs, :lifetime_max_uses, nil)
        true -> cs
      end

    cs =
      cond do
        t != "period_once" -> put_change(cs, :period_unit, nil)
        true -> cs
      end

    cs = if t != "every_n_pulls", do: put_change(cs, :every_n_pulls, nil), else: cs

    if e == "pity" do
      put_change(cs, :discount_percent, 0)
    else
      cs
    end
  end

  def effect_types, do: @effect_types
  def trigger_types, do: @trigger_types
  def period_units, do: @period_units
end
