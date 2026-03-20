defmodule Marbles.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def change do
    # Guilds/servers (Discord, Matrix, etc.)
    create table(:guilds, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :platform, :string, null: false, default: "discord"
      add :image_url, :string
      timestamps()
    end

    # Discord channel spawn config (channel_id is Discord snowflake)
    create table(:channels, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :guild_id, references(:guilds, type: :string, on_delete: :delete_all), null: false
      add :spawn_rate, :float, default: 0.0, null: false
      timestamps()
    end

    create index(:channels, [:guild_id])

    # Teams
    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :logo_path, :string
      add :color_hex, :string
      timestamps()
    end

    create unique_index(:teams, [:name])

    # Internal users (one per person; multiple platform logins link here)
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :display_name, :string
      add :currency, :integer, default: 0
      add :role, :string, null: false, default: "regular"
      timestamps()
    end

    # Platform identities (Discord, Google, Matrix, etc.) linking to internal user
    create table(:user_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :platform_id, :string, null: false
      add :username, :string, null: false
      timestamps()
    end

    create unique_index(:user_identities, [:platform, :platform_id])
    create index(:user_identities, [:user_id])

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
      add :banner_path, :string

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

    create table(:pack_pull_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pack_id, references(:packs, type: :binary_id, on_delete: :delete_all), null: false
      add :effect_type, :string, null: false
      add :discount_percent, :integer, null: false, default: 0
      add :min_rarity, :integer
      add :apply_1x, :boolean, null: false, default: true
      add :apply_10x, :boolean, null: false, default: true
      add :trigger_type, :string, null: false
      add :lifetime_max_uses, :integer
      add :period_unit, :string
      add :every_n_pulls, :integer
      add :starts_at, :utc_datetime_usec
      add :ends_at, :utc_datetime_usec
      timestamps()
    end

    create index(:pack_pull_rules, [:pack_id])

    create table(:user_pack_pull_rule_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :rule_id, references(:pack_pull_rules, type: :binary_id, on_delete: :delete_all),
        null: false

      add :uses_consumed, :integer, null: false, default: 0
      add :period_bucket, :string
      add :pulls_accumulated, :integer, null: false, default: 0
      timestamps()
    end

    create unique_index(:user_pack_pull_rule_states, [:user_id, :rule_id])
    create index(:user_pack_pull_rule_states, [:rule_id])

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

    # Daily streaks
    create table(:user_daily_streaks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :last_claimed_at, :utc_datetime_usec
      add :current_streak, :integer, default: 0
      add :longest_streak, :integer, default: 0
      timestamps()
    end

    create unique_index(:user_daily_streaks, [:user_id])
    create index(:user_daily_streaks, [:last_claimed_at])

    # User inventory for generic items (boosts, skins, etc.)
    create table(:user_inventory, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :item_type, :string, null: false
      add :item_id, :string, null: false
      add :quantity, :integer, default: 1
      add :meta, :map, default: %{}
      timestamps()
    end

    create index(:user_inventory, [:user_id])
    create index(:user_inventory, [:user_id, :item_type])

    # Analytics (dev adapter): pulls and spawns; prod can use a different adapter
    # guild_id/channel_id as string for Discord snowflakes
    create table(:analytics_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :guild_id, :string
      add :channel_id, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :meta, :map, default: %{}
      timestamps()
    end

    create index(:analytics_events, [:event_type, :inserted_at])
    create index(:analytics_events, [:guild_id, :inserted_at])
  end
end
