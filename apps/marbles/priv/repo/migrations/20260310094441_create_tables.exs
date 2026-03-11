defmodule Marbles.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def change do
    # Teams
    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :logo_url, :string
      add :color_hex, :string
      timestamps()
    end

    create unique_index(:teams, [:name])

    # Users
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :display_name, :string
      add :platform, :string, null: false
      add :platform_id, :string, null: false
      add :currency, :integer, default: 0
      add :role, :string, null: false, default: "regular"
      timestamps()
    end

    create unique_index(:users, [:username])
    create unique_index(:users, [:platform, :platform_id])

    # Marbles (The Templates)
    create table(:marbles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :edition, :string, default: "Standard"
      # Stored as string for Ecto.Enum
      add :role, :string, null: false
      add :rarity, :integer, null: false
      add :base_stats, :map, default: "{}"
      add :team_id, references(:teams, type: :binary_id, on_delete: :nilify_all)
      timestamps()
    end

    # Packs
    create table(:packs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :cost, :integer, default: 0
      add :start_date, :date, null: true
      add :end_date, :date, null: true
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:packs, [:name])

    # Pack contents Join Table (many-to-many)
    create table(:pack_contents, primary_key: false) do
      add :pack_id, references(:packs, type: :binary_id, on_delete: :delete_all), null: false
      add :marble_id, references(:marbles, type: :binary_id, on_delete: :delete_all), null: false
    end

    # Composite index for faster lookups and to prevent duplicate entries
    create unique_index(:pack_contents, [:pack_id, :marble_id])

    # Marble Assets
    create table(:marble_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # thumb, splash, etc.
      add :type, :string, null: false
      add :filename, :string, null: false
      add :version, :integer, default: 1

      # Link to the marble
      add :marble_id, references(:marbles, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    # Indexing marble_id is vital for performance when preloading assets
    create index(:marble_assets, [:marble_id])
    # ensure a marble doesn't have two 'splash' images
    create unique_index(:marble_assets, [:marble_id, :type])

    # User Collection (The "Owned" Marbles)
    create table(:user_marbles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :marble_id, references(:marbles, type: :binary_id, on_delete: :delete_all)
      add :level, :integer, default: 1
      add :experience, :integer, default: 0
      add :meta, :map, default: "{}"
      timestamps()
    end

    create index(:user_marbles, [:user_id])
    create index(:user_marbles, [:marble_id])
  end
end
