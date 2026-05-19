defmodule Marbles.Schema.AuditLog do
  @moduledoc """
  Single row in the system-wide audit trail. Written asynchronously by
  `Marbles.Audit`. Retained for 30 days then pruned by the cleanup task.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          actor_id: Ecto.UUID.t() | nil,
          action: String.t() | nil,
          target_type: String.t() | nil,
          target_id: String.t() | nil,
          before: map() | nil,
          after: map() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  schema "audit_logs" do
    field :actor_id, :binary_id
    field :action, :string
    field :target_type, :string
    field :target_id, :string
    field :before, :map
    field :after, :map
    field :metadata, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
