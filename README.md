# Marbles

A marbles collection bot and game system. Core domain and gacha engine live in `apps/marbles`; a Phoenix app provides the admin panel and future client-side race game; a Discord bot exposes collection and gacha via slash commands. The design is loosely coupled so you can run locally with SQLite and no external services, or scale in production with a distributed supervision tree and a different database.

## Architecture

- **`apps/marbles`** — Core: Ecto repo, schemas (users, teams, marbles, packs, user_marbles, marble_assets), contexts (Catalog, Collection, Accounts), and the gacha engine. Single source of truth for data and pull logic.
- **`apps/marbles_web`** — Phoenix app: admin panel for the core, and (planned) a client-side 3D race game (e.g. Three.js) with physics on racetracks.
- **`apps/marbles_discordbot`** — Discord bot (Nostrum): slash commands for pull, trade, analytics; talks to the Marbles core for gacha and collection.

Dev: SQLite, one node, no extra services. Prod: configurable DB path and pool, optional DNS-based clustering; the core can be swapped to a sharded or beefier DB by changing Repo config and migrations.

## Requirements

- Elixir and Erlang (e.g. via [mise](https://mise.jdx.dev/) — see `mise.toml`).
- For Discord: a bot token.

## Setup

From the project root:

```bash
mix setup
```

This installs and sets up dependencies for all umbrella apps. Then:

1. Copy `.env.example` to `.env` and set `DISCORD_BOT_TOKEN` if you will run the Discord bot.
2. Run migrations and seeds from the marbles app:

   ```bash
   mix ecto.setup
   ```

3. Start everything (interactive):

   ```bash
   iex -S mix
   ```

   Or start only the web app (no Discord):

   ```bash
   cd apps/marbles_web && iex -S mix phx.server
   ```

Web UI: [http://localhost:4000](http://localhost:4000).

## Configuration

- **Development** — SQLite DB path and pool are in `config/dev.exs`. No `DATABASE_PATH` required.
- **Production** — Set in `config/runtime.exs` (or env):
  - `DATABASE_PATH` — path to the SQLite DB file (e.g. `/etc/marbles/marbles.db`).
  - `SECRET_KEY_BASE` — for Phoenix (e.g. `mix phx.gen.secret`).
  - `DISCORD_BOT_TOKEN` — required if the Discord app is started.
  - Optional: `PORT`, `POOL_SIZE`, `DNS_CLUSTER_QUERY` for clustering.

Secrets and env-based config only; no credentials in the repo.

## Releases

A single OTP release runs all three apps:

```bash
mix release marbles_umbrella
```

Start with `./_build/prod/rel/marbles_umbrella/bin/marbles_umbrella start`. For production, set `DATABASE_PATH`, `SECRET_KEY_BASE`, and `DISCORD_BOT_TOKEN` in the environment.

## Roadmap

- **Admin panel** — Manage teams, marbles, packs, and catalog from the Phoenix app.
- **Discord** — Full handling of `/pull`, `/trade`, `/analytics` using the core gacha and collection APIs.
- **3D race game** — Client-side physics simulation (Three.js or similar) of marbles on a racetrack; racecourses to be extracted from Jelle’s Marble Runs–style footage (e.g. via Meshroom) as 3D models, then loaded into the viewer with physics and game logic.

## Project layout

```sh
tree -I  '_build|.elixir_ls|deps|node_modules|dist'
```

## Checks

From the root:

```bash
mix precommit
```

Runs compile with warnings-as-errors, dependency cleanup, format, and tests across the umbrella.

## Assets

Use [rclone](https://github.com/rclone/rclone) and an S3 Compatible bucket (e.g. Cloudflare R2) to store assets, 
with a confiuration like this:

```conf
[r2]
type = s3
provider = Cloudflare
access_key_id = <access_key_id>
secret_access_key = <secret_access_key>
region = auto
endpoint = <s3_endpoint>
```

To mount the bucket locally:
```bash
RCLONE_CONF_NAME=r2
R2_BUCKET_NAME=marbles-umbrella
MOUNT_DIR=./mnt-r2
mkdir -p "$MOUNT_DIR"
rclone mount "$RCLONE_CONF_NAME:$R2_BUCKET_NAME" "$MOUNT_DIR" \
  --vfs-cache-mode full \
  --vfs-cache-max-size 10G
```
When terminating the process the mount will be automatically unmounted (unless busy),
add the `--daemon` flag to run in the background.

To unmount it:
```bash
MOUNT_DIR=./mnt-r2
fusermount -u "$MOUNT_DIR"
```

NEVER RUN `sudo rm -rf $MOUNT_DIR` as it would delete the files in the cloud storage.
