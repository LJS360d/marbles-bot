defmodule Marbles.Schema.InboxMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inbox_messages" do
    field :title, :string
    field :body, :string
    field :type, Ecto.Enum, values: [:info, :reward, :announcement], default: :info
    field :data, :map, default: %{}
    field :read_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    belongs_to :user, Marbles.Schema.User

    timestamps()
  end

  @type t :: %__MODULE__{
          id: binary() | nil,
          title: String.t() | nil,
          body: String.t() | nil,
          type: atom() | nil,
          data: map() | nil,
          read_at: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          user_id: binary() | nil,
          user: Ecto.Association.NotLoaded.t() | Marbles.Schema.User.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  def changeset(inbox_message, attrs) do
    inbox_message
    |> cast(attrs, [
      :user_id,
      :title,
      :body,
      :type,
      :data,
      :read_at,
      :expires_at
    ])
    |> validate_required([:user_id, :title, :body])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:body, min: 1)
  end
end
