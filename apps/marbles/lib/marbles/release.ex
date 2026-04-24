defmodule Marbles.Release do
  @moduledoc """
  Release tasks (migrate / seed). Use from deploy hooks or one-off `bin/<release> eval`.

  Seeding is skipped when at least one team row exists so a post-deploy hook can run safely
  on every deploy after the first successful seed.
  """
  @app :marbles

  alias Marbles.Repo
  alias Marbles.Schema.Team

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @spec seed() :: :ok
  def seed do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    if has_teams?() do
      :ok
    else
      seeds = Application.app_dir(@app, "priv/repo/seeds.exs")
      Code.eval_file(seeds)
      :ok
    end
  end

  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  defp has_teams? do
    Repo.aggregate(Team, :count, :id) > 0
  rescue
    _ -> false
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
