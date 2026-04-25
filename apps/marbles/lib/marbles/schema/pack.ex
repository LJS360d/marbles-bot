defmodule Marbles.Schema.Pack do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type role :: :regular | :server_admin | :owner
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          cost: integer(),
          banner_path: String.t(),
          pull_rules: Ecto.Association.NotLoaded.t() | [Marbles.Schema.PackPullRule.t()] | nil,
          marbles: Ecto.Association.NotLoaded.t() | [Marbles.Schema.Marble.t()] | nil,
          start_date: NaiveDateTime.t() | nil,
          end_date: NaiveDateTime.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "packs" do
    field :name, :string
    field :description, :string
    field :cost, :integer
    field :start_date, :date
    field :end_date, :date
    field :banner_path, :string

    many_to_many :marbles, Marbles.Schema.Marble,
      join_through: "pack_contents",
      on_replace: :delete

    has_many :pull_rules, Marbles.Schema.PackPullRule

    timestamps()
  end

  def changeset(pack, attrs) do
    pack
    |> cast(attrs, [:name, :description, :cost, :start_date, :end_date, :banner_path])
    |> validate_required([:name, :cost])
  end
end
