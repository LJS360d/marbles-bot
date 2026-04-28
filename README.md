# Marbles

Marbles is a collection game platform with three umbrella apps:

- `apps/marbles` — core domain, economy, gacha, storage, analytics.
- `apps/marbles_web` — Phoenix web/admin UI and owner tooling.
- `apps/marbles_discordbot` — Nostrum Discord bot with slash commands, spawn/catch flow, and interactive pull sessions.

The stack is SQLite-friendly for low-cost deployments, with S3-compatible storage support for assets.

## Architecture

- **Core (`apps/marbles`)**
  - Accounts and Discord identity linking.
  - Catalog: teams, marbles, packs, pack pull rules.
  - Gacha pull engine with pity/rule hooks.
  - Collection ownership, duplicate conversion to dust.
  - Economy: daily streaks, mining, upgrades, boosts, shop, leaderboards.
  - Analytics event recording.
- **Web (`apps/marbles_web`)**
  - Discord OAuth login.
  - Guild admin pages.
  - Owner admin pages for users, marbles, packs, teams, economy, shop overrides.
  - Owner broadcast endpoints/UI.
- **Discord bot (`apps/marbles_discordbot`)**
  - Global slash command registration/sync.
  - Message-driven spawn system with reaction-based catch.
  - Interactive components for collection pagination and pull sessions.
  - Command resync subscriber via PubSub.

## Requirements

- Elixir + Erlang (see `mise.toml`).
- Discord bot token for bot features.

## Local setup

From repository root:

```bash
mix setup
mix ecto.setup
iex -S mix
```

Web UI runs at [http://localhost:4000](http://localhost:4000).

## Discord Activities local testing (`cloudflared`)

Discord Embedded Activities require a public HTTPS URL. Local `localhost` is not enough.

### Prerequisites

- Install `cloudflared` locally.
- Start the web app on port `4000`.
- Add activity env keys in local `.env`:
  - `DISCORD_ACTIVITY_ENABLED=true`
  - `DISCORD_ACTIVITY_CLIENT_ID=<discord_application_id>`
  - `DISCORD_ACTIVITY_CLIENT_SECRET=<discord_client_secret>`
  - `DISCORD_ACTIVITY_REDIRECT_URI=https://<public-host>/discord/activity/callback`
  - `DISCORD_ACTIVITY_ALLOWED_ORIGINS=https://discord.com,https://ptb.discord.com,https://canary.discord.com`
  - `DISCORD_ACTIVITY_SESSION_SAME_SITE=None`

### Start tunnel

```bash
cloudflared tunnel --url http://localhost:4000
```

Use the generated `https://<random>.trycloudflare.com` host as `<public-host>`.

### Discord Developer Portal values (required)

- **OAuth2 Redirect URIs**
  - `https://<public-host>/auth/discord/callback`
  - `https://<public-host>/discord/activity/callback`
- **Embedded App / Activity Launch URL**
  - `https://<public-host>/activities/pulling`
- **Allowed origins/domains**
  - `https://discord.com`
  - `https://ptb.discord.com`
  - `https://canary.discord.com`

When the `trycloudflare.com` hostname changes, update Portal URLs and `DISCORD_ACTIVITY_REDIRECT_URI` to the new host.

## Configuration

Use `.env.example` as source of truth for env keys.

- **Core prod keys**
  - `DATABASE_PATH` (SQLite file path)
  - `POOL_SIZE`
  - `ASSETS_BASE_URL`
  - `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_HOST`, `S3_REGION`, `S3_PORT`, `S3_SCHEME`, `S3_PATH_STYLE`
- **Web prod keys**
  - `SECRET_KEY_BASE`
  - `PHX_HOST` (or `RAILWAY_PUBLIC_DOMAIN`)
  - `PHX_SCHEME`, `PHX_URL_PORT`, `PORT`
- **Bot prod keys**
  - `DISCORD_BOT_TOKEN`
- **Release selection**
  - `RELEASE_NAME=web|bot|marbles_umbrella`
  - `RELEASE_ROLE` is optional and inferred from `RELEASE_NAME`.

## Deployment strategy (Railway)

Read and follow `railway.toml` first. It documents the current production strategy and constraints.

Key points:

- SQLite must live on a mounted volume: `/app/data` + `DATABASE_PATH=/app/data/marbles_prod.db`.
- Migrations and first-seed run from `docker-entrypoint.sh`, not Railway predeploy hooks.
- Reason: predeploy jobs often run without mounted service volume, causing ephemeral SQLite writes.
- Startup path is: mount volume -> entrypoint migrate -> conditional seed -> app start.
- Seeding is guarded in `Marbles.Release.seed/0` (no-op when teams already exist).

### Service topologies

- **Single service**
  - `RELEASE_NAME=marbles_umbrella` to run web + bot in one container.
- **Split services**
  - Web service: `RELEASE_NAME=web`.
  - Bot service: `RELEASE_NAME=bot`.
  - If both use SQLite, both must target the same mounted DB path semantics.

## Discord bot features (complete)

This section reflects current command and consumer handlers in `apps/marbles_discordbot`.

### Command system and lifecycle

- Commands are declared in `MarblesDiscordbot.Commands`.
- On `READY`, bot syncs slash commands (`bulk_overwrite_global_commands` when needed).
- A PubSub subscriber (`commands_resync`) can force command re-sync at runtime.

### Slash commands

- `/pull pack:<pack>`
  - Opens a pull session with interactive buttons.
  - Uses pack pull pricing/rules and pity integration.
- `/packs`
  - Paginated active pack browser with `Previous`, `Next`, and `Pull` button.
- `/collection [user]`
  - Displays collection entries with pagination and sorting controls:
    - By rarity
    - By level
    - By name
- `/profile [user]`
  - Wallet, dust, owned count, streak, mine roster, active boosts.
- `/balance`
  - Quick wallet view (coins + dust).
- `/daily`
  - Claims streak reward + mining payout + mining XP allocation.
- `/boosts [user]`
  - Lists active timed effects and remaining duration.
- `/leaderboard [kind]`
  - `coins` or `collection`.
- `/mines <view|add|remove|clear>`
  - Manages mining roster (max 5 slots).
  - Autocomplete for add/remove marble names.
- `/upgrades <view|buy>`
  - Permanent progression upgrades purchased with dust:
    - `mine_yield`
    - `mine_cap`
    - `dust_gain`
    - `spawn_luck`
- `/shop <list|buy>`
  - Timed boosts with coin/dust prices and per-period limits.
  - Backed by default products + DB overrides (`shop_items`).
- `/spawnrate <list|set>`
  - Guild channel spawn rate management.
  - `set` accepts optional channel and percentage.
- `/analytics`
  - Pull/spawn counters (global + guild context), bot/core versions.
- `/trade`
  - Placeholder only; currently returns “not implemented yet.”

### Spawn/catch loop

- On eligible guild text messages, bot rolls channel spawn chance.
- If roll passes:
  - Spawns random marble.
  - Posts embed with random required emoji.
  - Creates pending spawn state with 5-minute expiry.
- On matching reaction:
  - First valid claimer gets ownership/rewards.
  - Duplicates are converted to dust.
  - Spawn message is edited with result and rewards.

### Pull session behavior

- Pull buttons are ownership-locked to the initiator.
- Supports single pull and 10x pull.
- Uses pack pull rules for pricing and pity behavior.
- Deducts currency only after successful pulls.
- Converts duplicates to dust.
- Edits/rotates component rows to avoid stale interaction conflicts.

### Economy behavior exposed through bot

- **Coins (`🪙`)** primary spend currency.
- **Dust (`✨`)** duplicate conversion + upgrades/shop currency.
- **Daily streaks** with capped streak bonus.
- **Mining** accrues between claims; affected by upgrades and active boosts.
- **Timed effects** stack/extend via shop purchases.
- **Leaderboards** for wealth and collection breadth.

### Bot process composition

- Consumers:
  - events
  - messages
  - reactions
  - slash interactions
  - component interactions
- Distributed helpers:
  - Horde registry/supervisor for pending spawn state.
- Presence:
  - Updates Discord status with guild/server count.

## Web/admin features

- `/admin`
  - Guild list and guild detail pages for authenticated server admins/owners.
- `/admin/owner`
  - Owner dashboard and management pages:
    - users list/detail/edit
    - marbles list/edit
    - packs list/create/edit
    - teams list/edit
    - economy dashboard
    - shop item overrides
- `/broadcast`
  - Owner broadcast panel.
- `/api/owner/stats` and `/api/owner/broadcast`
  - Owner API endpoints for dashboard/broadcast workflows.

## Releases

Build release:

```bash
mix release marbles_umbrella
```

Run:

```bash
./_build/prod/rel/marbles_umbrella/bin/marbles_umbrella start
```

For role-specific builds, set `RELEASE_NAME` accordingly.

## Checks

Run from root:

```bash
mix precommit
```

## Assets (R2 / S3-compatible)

Example `rclone` profile:

```conf
[r2]
type = s3
provider = Cloudflare
access_key_id = <access_key_id>
secret_access_key = <secret_access_key>
region = auto
endpoint = <s3_endpoint>
```

Mount locally:

```bash
RCLONE_CONF_NAME=r2
R2_BUCKET_NAME=marbles-umbrella
MOUNT_DIR=./mnt-r2
mkdir -p "$MOUNT_DIR"
rclone mount "$RCLONE_CONF_NAME:$R2_BUCKET_NAME" "$MOUNT_DIR" \
  --vfs-cache-mode full \
  --vfs-cache-max-size 10G
```

Unmount:

```bash
MOUNT_DIR=./mnt-r2
fusermount -u "$MOUNT_DIR"
```

Never run `sudo rm -rf $MOUNT_DIR` on a mounted remote.
