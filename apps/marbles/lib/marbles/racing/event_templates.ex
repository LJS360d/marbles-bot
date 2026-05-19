defmodule Marbles.Racing.EventTemplates do
  @moduledoc """
  CRUD context for event_templates — owner-defined blueprints used by
  the CronScheduler to materialize live `Marbles.Schema.Event` rows at
  each cron tick.

  A template is referenced by zero or more `Marbles.Schema.EventSchedule`
  rows (N:1). Templates carry no start/end_time; runtime windows come from
  `default_duration_seconds` + the schedule's `advance_seconds`.
  """

  import Ecto.Query

  alias Marbles.Repo
  alias Marbles.Schema.EventTemplate

  @type template_error :: :not_found

  @doc "Returns all templates."
  @spec list_all() :: [EventTemplate.t()]
  def list_all do
    from(t in EventTemplate, order_by: [desc: t.inserted_at])
    |> Repo.all()
  end

  @doc "Returns only active templates (for schedule dropdowns)."
  @spec list_active() :: [EventTemplate.t()]
  def list_active do
    from(t in EventTemplate, where: t.active == true, order_by: [asc: t.name])
    |> Repo.all()
  end

  @doc "Fetches a template by id. Returns {:error, :not_found} if missing."
  @spec get_template(Ecto.UUID.t()) :: {:ok, EventTemplate.t()} | {:error, :not_found}
  def get_template(id) do
    case Repo.get(EventTemplate, id) do
      nil -> {:error, :not_found}
      t -> {:ok, t}
    end
  end

  @spec create_template(map()) ::
          {:ok, EventTemplate.t()} | {:error, Ecto.Changeset.t()}
  def create_template(attrs) do
    %EventTemplate{}
    |> EventTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_template(EventTemplate.t(), map()) ::
          {:ok, EventTemplate.t()} | {:error, Ecto.Changeset.t()}
  def update_template(%EventTemplate{} = template, attrs) do
    template
    |> EventTemplate.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_template(EventTemplate.t()) ::
          {:ok, EventTemplate.t()} | {:error, Ecto.Changeset.t()}
  def delete_template(%EventTemplate{} = template) do
    Repo.delete(template)
  end
end
