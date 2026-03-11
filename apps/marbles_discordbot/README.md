# MarblesDiscordbot

Discord bot for the marbles collection system. Uses [Nostrum](https://github.com/Kraigie/nostrum); exposes slash commands that delegate to the core `marbles` app for gacha and collection.

## Commands (slash)

- **`/pull`** — Pull a random marble (gacha); intended to call `Marbles.Gacha.pull_from_pack/1` and `Marbles.Collection.add_marble_to_collection/3` (integration in progress).
- **`/trade`** — Trade a marble with another user (guild-only; target user option).
- **`/analytics`** — Show bot/catalog analytics.

Commands are synced with Discord via `MarblesDiscordbot.Commands.sync/0` (e.g. on Ready).

## Structure

- **Consumers** — `Ready` (startup, command sync), `Message`, `Interaction` (slash command handling). Interaction handler currently logs; gacha/collection calls will be wired here.
- **Config** — `DISCORD_BOT_TOKEN` is required at runtime (see root `.env.example` and `config/runtime.exs`). `youtubedl` and `streamlink` are set to `nil` in runtime config.

## Run

As part of the umbrella:

Or run only the bot (ensure `marbles` is started and DB is migrated):

```bash
iex -S mix
# from repo root, or from apps/marbles_discordbot with proper mix path
```

Set `DISCORD_BOT_TOKEN` in `.env` or the environment before starting.
