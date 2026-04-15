---
name: oc-on-cf
description: Deploy OpenClaw on Cloudflare using the `/deploy-openclaw` command. Includes the bundled `moltworker/` project, browser automation skills, and Google Workspace integration (gcloud + gws CLI).
---

# OC on CF Skill

Deploy a new OpenClaw AI bot on Cloudflare Workers + Containers. Bundles pre-configured source code, browser automation, and Google Workspace auth support.

## Primary Command

- `/deploy-openclaw`

## Three-Phase Workflow

### Phase 1: Admin — GCP Setup (one-time)

Admin follows [`docs/admin-gcp-setup.md`](docs/admin-gcp-setup.md) on their Mac:

1. `gcloud auth login`
2. `gws auth setup` — creates GCP project + enables Workspace APIs
3. Google Cloud Console — OAuth brand + Desktop App client + test users
4. Downloads `client_secret.json` (reusable across all bots)

### Phase 2: Admin — Deploy Bot (per bot)

Admin runs `/deploy-openclaw`. The skill asks for `client_secret.json` path (required), then:

- Creates R2 bucket, AI Gateway, Worker
- Sets 15 Worker Secrets (including `GWS_CLIENT_SECRET_JSON`)
- Deploys Worker + container
- Configures Telegram webhook

### Phase 3: Admin — Onboard User (per user)

After deployment, admin helps user with three pairing steps:

| Step | What | Who |
|------|------|-----|
| A | Telegram pair | admin approves pairing code |
| B | OpenClaw Dashboard pair | user enters Gateway Token, admin approves in admin panel |
| C | Google Workspace login | admin sends user the prompt from [`docs/user-gws-login.md`](docs/user-gws-login.md), user pastes to bot, agent runs `gws auth login` via agent-browser |

## What It Includes

| Path | Purpose |
|------|---------|
| `commands/deploy-openclaw.md` | Full deployment workflow (run via `/deploy-openclaw`) |
| `docs/admin-gcp-setup.md` | Admin GCP setup SOP (one-time, produces `client_secret.json`) |
| `docs/user-gws-login.md` | User-facing prompt for Google Workspace login (admin shares with user) |
| `moltworker/` | Pre-configured Cloudflare Worker + container project |
| `moltworker/skills/` | Bundled agent skills: `cloudflare-browser`, `agent-browser`, `gws-workspace` |

## What Gets Deployed

Each bot includes:

- **OpenClaw 2026.4.8** on Cloudflare Container (standard-3: 2 vCPU, 8 GiB)
- **Tools pre-installed**: Node.js 22, pnpm, gcloud CLI, gws CLI (musl), agent-browser + Chrome
- **Skills**: cloudflare-browser, agent-browser, gws-workspace
- **R2 persistence**: config, workspace, skills, `.config/` all backed up with incremental sync + hourly full sync
- **Channels**: Telegram (more can be added later)

## Requirements

- macOS (deployment environment)
- Cloudflare Workers Paid Plan ($5/month, required for Containers)
- Docker Desktop
- Google Cloud project with OAuth client (from Phase 1)
- Telegram Bot Token (from @BotFather)

## Notes

- `client_secret.json` from Phase 1 is **shared across all bots** (no need to regenerate per bot).
- User's Google OAuth credentials are stored **inside each bot's container** at `~/.config/gws/credentials.enc` and backed up to R2 — persists across container restarts.
- Each bot is **1-bot-1-user** (one bot pairs with one Google account).
