defmodule Marbles.Schema.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          spawn_rate: float() | nil,
          guild_id: String.t() | nil,
          guild: Ecto.Association.NotLoaded.t() | map() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "channels" do
    field :name, :string
    field :spawn_rate, :float, default: 0.0
    belongs_to :guild, Marbles.Schema.Guild, type: :string
    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:id, :guild_id, :name, :spawn_rate])
    |> validate_required([:id, :guild_id, :name])
    |> validate_number(:spawn_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:guild_id)
  end
end
