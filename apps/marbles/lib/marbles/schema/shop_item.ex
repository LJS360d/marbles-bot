defmodule Marbles.Schema.ShopItem do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "shop_items" do
    field :enabled, :boolean, default: true
    field :coin_price, :integer
    field :dust_price, :integer
    field :duration_sec, :integer
    field :limit_count, :integer
    field :limit_period_unit, :string
    field :label_override, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(shop_item, attrs) do
    shop_item
    |> cast(attrs, [
      :id,
      :enabled,
      :coin_price,
      :dust_price,
      :duration_sec,
      :limit_count,
      :limit_period_unit,
      :label_override
    ])
    |> validate_required([:id, :enabled])
    |> validate_number(:coin_price, greater_than_or_equal_to: 0)
    |> validate_number(:dust_price, greater_than_or_equal_to: 0)
    |> validate_number(:duration_sec, greater_than: 0)
    |> validate_number(:limit_count, greater_than: 0)
    |> validate_inclusion(:limit_period_unit, ["day", "week", "month"])
  end
end
