defmodule Marbles.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def change do
    create table(:guilds, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :platform, :string, null: false, default: "discord"
      add :image_url, :string
      timestamps()
    end

    create table(:channels, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :guild_id, references(:guilds, type: :string, on_delete: :delete_all), null: false
      add :spawn_rate, :float, default: 0.0, null: false
      timestamps()
    end

    create index(:channels, [:guild_id])

    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :logo_path, :string
      add :color_hex, :string
      timestamps()
    end

    create unique_index(:teams, [:name])

    create table(:marbles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :edition, :string, default: "Standard"
      add :role, :string, null: false
      add :rarity, :integer, null: false
      add :base_stats, :map, default: %{}
      add :team_id, references(:teams, type: :binary_id, on_delete: :nilify_all)
      timestamps()
    end

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :display_name, :string
      add :currency, :integer, default: 0
      add :dust, :integer, default: 0, null: false
      add :mine_roster, :map, default: %{}, null: false
      add :role, :string, null: false, default: "regular"
      add :elo, :integer, default: 1000
      add :last_marble_id, references(:marbles, type: :binary_id, on_delete: :nilify_all)
      add :race_wins, :integer, default: 0
      add :race_losses, :integer, default: 0
      add :races_entered, :integer, default: 0
      add :total_currency_won, :integer, default: 0
      add :total_currency_wagered, :integer, default: 0
      add :highest_elo, :integer, default: 1000
      add :current_streak, :integer, default: 0
      add :best_streak, :integer, default: 0
      timestamps()
    end

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

    create table(:pack_contents, primary_key: false) do
      add :pack_id, references(:packs, type: :binary_id, on_delete: :delete_all), null: false
      add :marble_id, references(:marbles, type: :binary_id, on_delete: :delete_all), null: false
    end

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

    create table(:marble_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :filename, :string, null: false
      add :version, :integer, default: 1
      add :marble_id, references(:marbles, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:marble_assets, [:marble_id])
    create unique_index(:marble_assets, [:marble_id, :type])

    create table(:user_marbles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :marble_id, references(:marbles, type: :binary_id, on_delete: :delete_all)
      add :level, :integer, default: 1
      add :experience, :integer, default: 0
      add :meta, :map, default: %{}
      timestamps()
    end

    create index(:user_marbles, [:user_id])
    create index(:user_marbles, [:marble_id])
    create unique_index(:user_marbles, [:user_id, :marble_id])
    create index(:user_marbles, [:user_id, :level, :experience])

    create table(:user_upgrades, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :upgrade_key, :string, null: false
      add :level, :integer, null: false, default: 0
      timestamps()
    end

    create unique_index(:user_upgrades, [:user_id, :upgrade_key])
    create index(:user_upgrades, [:upgrade_key])

    create table(:user_effects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :effect_key, :string, null: false
      add :scope, :string, null: false, default: "account"
      add :guild_id, :string
      add :expires_at, :utc_datetime_usec, null: false
      add :meta, :map, default: %{}, null: false
      timestamps()
    end

    create index(:user_effects, [:user_id])
    create index(:user_effects, [:user_id, :effect_key])
    create index(:user_effects, [:expires_at])

    create table(:shop_items, primary_key: false) do
      add :id, :string, primary_key: true
      add :enabled, :boolean, null: false, default: true
      add :coin_price, :integer
      add :dust_price, :integer
      add :duration_sec, :integer
      add :limit_count, :integer
      add :limit_period_unit, :string
      add :label_override, :string
      timestamps()
    end

    create table(:caught_spawns, primary_key: false) do
      add :message_id, :string, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(updated_at: false)
    end

    create index(:caught_spawns, [:user_id])

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

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :start_time, :utc_datetime_usec, null: false
      add :end_time, :utc_datetime_usec, null: false
      add :banner_path, :string
      add :event_type, :string, null: false, default: "scheduled_race"
      add :config, :map, default: %{}
      add :active, :boolean, default: true
      timestamps()
    end

    create index(:events, [:start_time])
    create index(:events, [:active])
    create index(:events, [:event_type])

    create table(:event_registrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, default: "registered"
      add :final_position, :integer
      add :payout, :integer, default: 0
      timestamps()
    end

    create unique_index(:event_registrations, [:event_id, :user_id])
    create index(:event_registrations, [:user_id])
    create index(:event_registrations, [:event_id])

    create table(:inbox_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :type, :string, default: "info"
      add :data, :map, default: %{}
      add :read_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      timestamps()
    end

    create index(:inbox_messages, [:user_id])
    create index(:inbox_messages, [:user_id, :read_at])

    create table(:race_tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :track_model_path, :string
      add :thumbnail_path, :string
      add :start_positions, :map, default: %{}
      add :checkpoints, :map, default: %{}
      add :finish_line, :map, default: %{}
      add :difficulty, :integer, default: 1
      add :max_players, :integer, default: 100
      add :active, :boolean, default: true
      timestamps()
    end
  end
end
