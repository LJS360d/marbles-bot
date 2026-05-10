defmodule Marbles.Schema.EventRegistration do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_registrations" do
    field :status, Ecto.Enum,
      values: [:registered, :checked_in, :disqualified, :withdrawn],
      default: :registered

    field :final_position, :integer
    field :payout, :integer, default: 0

    belongs_to :event, Marbles.Schema.Event
    belongs_to :user, Marbles.Schema.User

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          status: :registered | :checked_in | :disqualified | :withdrawn | nil,
          final_position: integer() | nil,
          payout: integer() | nil,
          event_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          event: Ecto.Association.NotLoaded.t() | Marbles.Schema.Event.t() | nil,
          user: Ecto.Association.NotLoaded.t() | Marbles.Schema.User.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  def changeset(event_registration, attrs) do
    event_registration
    |> cast(attrs, [:event_id, :user_id, :status, :final_position, :payout])
    |> validate_required([:event_id, :user_id])
    |> validate_number(:final_position, greater_than: 0)
    |> validate_number(:payout, greater_than_or_equal_to: 0)
    |> unique_constraint([:event_id, :user_id], name: :event_registrations_event_id_user_id_index)
  end
end
