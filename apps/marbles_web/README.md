# MarblesWeb

Phoenix application for the marbles system: administration panel for the core (teams, marbles, packs, catalog) and the future client-side 3D race game.

## What it does

- **Admin panel** — Manage core data and configuration (planned: LiveView-based CRUD for teams, marbles, packs, and catalog).
- **Race game (planned)** — Client-side 3D experience (Three.js or similar): physics simulation of marbles on a racetrack. Racecourses will be derived from external sources (e.g. Jelle’s Marble Runs–style footage) as 3D models (e.g. via Meshroom), then loaded into the viewer; physics and game logic to be added later.

## Run

From the repo root:

```bash
mix phx.server
```

Or from this app:

```bash
cd apps/marbles_web && mix phx.server
```

Open [http://localhost:4000](http://localhost:4000). The core `marbles` app must be available (same umbrella); run migrations and seeds in `apps/marbles` if needed.

## Stack

- Phoenix (Bandit), LiveView, Tailwind. Uses the shared `Marbles` context and gacha engine; no direct Ecto in the web app where a context exists.
