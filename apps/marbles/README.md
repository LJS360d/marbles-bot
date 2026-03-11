# Marbles (core)

Core library for the marbles collection system: database access, domain logic, and the gacha engine. All other apps (Phoenix, Discord bot) depend on this; it stays free of HTTP or Discord concerns so it can be reused in different topologies (single node, distributed, different DB backends).

## Responsibilities

- **Persistence** — Ecto repo and migrations. SQLite in dev/test; production DB path and pool are configurable (e.g. swap to PostgreSQL by changing adapter and config).
- **Domain** — Schemas: `User`, `Team`, `Marble`, `Pack`, `UserMarble`, `MarbleAsset`. Many-to-many marbles ↔ packs via `pack_contents`.
- **Contexts**
  - **Catalog** — Read (and limited write) for teams, marbles, packs; e.g. `list_teams`, `list_pack_marbles_by_rarity`, `get_marble!`.
  - **Collection** — User inventory: `list_user_inventory`, `add_marble_to_collection`, `get_user_marble!`.
  - **Accounts** — User identity and platform linkage (e.g. Discord).
- **Gacha** — `Marbles.Gacha.pull_from_pack(pack_id)`: weighted rarity roll, then random marble from that pack/rarity pool. Returns `{:ok, marble}` or `{:error, :empty_pool}`.

## Usage

Other apps call the contexts and `Marbles.Gacha`; they do not use the Repo or schemas directly when a context exists. Example:

```elixir
# Pull from a pack (e.g. from Discord or admin)
{:ok, marble} = Marbles.Gacha.pull_from_pack(pack_id)
Marbles.Collection.add_marble_to_collection(user_id, marble.id, %{source: "discord_pull"})
```

## Data

- **Seeds** — `priv/repo/seeds.exs` loads `priv/data/teams.json` and `priv/data/packs.json` (teams, marbles, assets, pack contents). Run with `mix ecto.setup` or `mix run priv/repo/seeds.exs` from this app.
- **Migrations** — Under `priv/repo/migrations/`. Run from project root or from `apps/marbles` with the umbrella config.

## Configuration

Repo and Ecto repos are configured in the umbrella `config/`. Dev uses a local SQLite path in `config/dev.exs`; prod uses `DATABASE_PATH` and optional `POOL_SIZE` from `config/runtime.exs`. DNS-based clustering is optional via `config :marbles, :dns_cluster_query`.
