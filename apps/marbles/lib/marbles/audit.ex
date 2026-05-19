defmodule Marbles.Audit do
  @moduledoc """
  System-wide audit log. Writes are fire-and-forget through a supervised
  Task — never blocks the caller's hot path. Reads are paginated and
  filterable from the admin UI.

  Retention: 30 days (see `cleanup_expired/0`, scheduled in
  `Marbles.Application`).
  """

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Schema.AuditLog

  @retention_days 30

  @type log_opts :: [
          actor_id: Ecto.UUID.t() | nil,
          target_type: String.t() | nil,
          target_id: term() | nil,
          before: map() | nil,
          after: map() | nil,
          metadata: map()
        ]

  @doc """
  Records an audit entry asynchronously. Returns immediately; the actual
  insert runs in the `Marbles.AuditTaskSupervisor` task tree. If the audit
  write fails, the failure is logged but does not affect the caller.

  Example:

      Audit.log("user.wallet.set",
        actor_id: owner_id,
        target_type: "user",
        target_id: user.id,
        before: %{coins: 10},
        after: %{coins: 100}
      )
  """
  @spec log(String.t(), log_opts()) :: :ok
  def log(action, opts \\ []) when is_binary(action) do
    row = %{
      action: action,
      actor_id: Keyword.get(opts, :actor_id),
      target_type: Keyword.get(opts, :target_type),
      target_id: stringify(Keyword.get(opts, :target_id)),
      before: Keyword.get(opts, :before),
      after: Keyword.get(opts, :after),
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: DateTime.utc_now()
    }

    Task.Supervisor.start_child(Marbles.AuditTaskSupervisor, fn ->
      try do
        Repo.insert_all(AuditLog, [row])
      rescue
        e ->
          require Logger
          Logger.error("Audit insert failed: #{inspect(e)}; row=#{inspect(row)}")
      end
    end)

    :ok
  end

  @doc """
  Lists audit log entries with filters and pagination.

  Filter keys (all optional):
  - `:actor_id` — exact match
  - `:target_type` — exact match
  - `:target_id` — exact match
  - `:action` — exact match
  - `:from` / `:to` — DateTime range on inserted_at
  - `:limit` (default 50)
  - `:offset` (default 0)

  Returns `{entries, total_count}`.
  """
  @spec list(map() | keyword()) :: {[AuditLog.t()], non_neg_integer()}
  def list(filters \\ %{}) do
    filters = Map.new(filters)
    limit = Map.get(filters, :limit, 50)
    offset = Map.get(filters, :offset, 0)

    base =
      from(a in AuditLog)
      |> filter_eq(:actor_id, Map.get(filters, :actor_id))
      |> filter_eq(:target_type, Map.get(filters, :target_type))
      |> filter_eq(:target_id, Map.get(filters, :target_id))
      |> filter_eq(:action, Map.get(filters, :action))
      |> filter_after(:inserted_at, Map.get(filters, :from))
      |> filter_before(:inserted_at, Map.get(filters, :to))

    total = Repo.aggregate(base, :count, :id)

    entries =
      base
      |> order_by([a], desc: a.inserted_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {entries, total}
  end

  @doc "Deletes log entries older than the retention window."
  @spec cleanup_expired() :: {non_neg_integer(), nil}
  def cleanup_expired do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days * 86_400, :second)

    from(a in AuditLog, where: a.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  defp filter_eq(query, _field, nil), do: query
  defp filter_eq(query, _field, ""), do: query

  defp filter_eq(query, field, value) do
    from(a in query, where: field(a, ^field) == ^value)
  end

  defp filter_after(query, _field, nil), do: query

  defp filter_after(query, field, %DateTime{} = dt) do
    from(a in query, where: field(a, ^field) >= ^dt)
  end

  defp filter_before(query, _field, nil), do: query

  defp filter_before(query, field, %DateTime{} = dt) do
    from(a in query, where: field(a, ^field) <= ^dt)
  end

  defp stringify(nil), do: nil
  defp stringify(v) when is_binary(v), do: v
  defp stringify(v), do: to_string(v)
end
