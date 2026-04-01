# Deploy OpenClaw

## What is this?

An **AI Skill** that automatically deploys an [OpenClaw](https://github.com/openclaw/openclaw) AI Bot on [Cloudflare](https://cloudflare.com). Give your AI agent (Claude Code, Claude Desktop, or OpenClaw itself) the `SKILL.md` file, and it handles everything — from installing tools to deploying your bot.

## What do you get?

After deployment, you have:

| What | Description |
|------|-------------|
| **Telegram AI Bot** | Your own AI assistant in Telegram — chat, ask questions, run tools |
| **Web Dashboard** | Browser-based control panel — view conversations, change settings, manage skills |
| **Admin Panel** | Monitor container health, R2 backups, paired devices, restart gateway |
| **Persistent Storage** | Conversations, config, and skills auto-sync to R2 — survives container restarts |

### What's running behind the scenes

| Component | Role | Analogy |
|-----------|------|---------|
| **[OpenClaw](https://github.com/openclaw/openclaw)** | Open-source AI agent — handles conversations, memory, tools, Telegram | The brain |
| **[Moltworker](https://github.com/cloudflare/moltworker)** | Cloudflare Worker — manages auth, routing, container lifecycle | The body |
| **AI Gateway** | Cloudflare proxy for AI requests — logging, rate limiting, auth | The shield |
| **R2 Storage** | Cloud object storage — persists data when container sleeps | The memory |

### How to use it

- **Telegram** — just send a message, the bot replies
- **Dashboard** — open `https://{name}.{subdomain}.workers.dev/?token={TOKEN}` in browser
- **Admin** — open `https://{name}.{subdomain}.workers.dev/_admin/` for container management

## Who is this for?

Anyone who wants their own AI bot but doesn't want to deal with infrastructure. You don't need to know how to code, use a terminal, or understand cloud services. Just talk to your AI agent and it handles the rest.

## How it works

```
You:  "Deploy a new AI bot for me"
AI:   Installing tools... creating resources... deploying...
AI:   "Done! Send 'hi' to your bot on Telegram."
You:  "hi"
Bot:  "Hey! I'm your new AI assistant. How can I help?"
```

The AI reads `SKILL.md` and follows 10 steps:

| Step | What happens | Who does it |
|------|-------------|-------------|
| 0 | Check & install prerequisites | AI (auto-fix) |
| 1 | Get account info + verify plan | AI |
| 2 | Copy source code | AI |
| 3 | Modify config (2 sed commands) | AI |
| 4 | Install dependencies | AI |
| 5 | Create cloud resources | AI + You (tokens) |
| 6 | Configure 14 secrets | AI |
| 7 | Build & deploy | AI |
| 8 | Set up Telegram webhook | AI |
| 9 | Pair Telegram + Dashboard | AI + You |

## What you need

- A **Mac** (macOS)
- A **Cloudflare account** with [Workers Paid Plan](https://dash.cloudflare.com/) ($5/month)
- **Telegram** installed on your phone or desktop

That's it. The AI installs everything else.

## Deployment flow

```mermaid
flowchart TD
    S0U1["Step 0.6 🔑 Create CF API Token<br/>(one-time setup)"]:::user --> S0A1["Step 0.1-0.4 Install tools<br/>brew, node, wrangler, docker"]:::auto
    S0U2["Step 0.7 🤖 Create Telegram Bot<br/>via BotFather"]:::user --> S1["Step 1 Get Account ID + Subdomain"]:::auto
    S0A1 --> S1
    S1 --> S1V["Step 1 Verify Workers Paid Plan"]:::auto
    S1V --> S2["Step 2 Copy source code"]:::auto
    S2 --> S3["Step 3 Modify files<br/>2 sed commands"]:::auto
    S3 --> S4["Step 4 Install dependencies<br/>npm install"]:::auto
    S4 --> S5AB["Step 5a-b Create R2 Bucket + AI Gateway"]:::auto
    S5AB --> S5C["Step 5c 🔑 Create AI Gateway Token<br/>in Dashboard"]:::user
    S5C --> S5D["Step 5d 🔑 Create R2 Token<br/>in Dashboard (optional)"]:::user
    S5D --> S6["Step 6 Configure 14 secrets"]:::auto
    S6 --> S7["Step 7 Build + Deploy<br/>3-5 minutes"]:::auto
    S7 --> S8["Step 8 Set Telegram webhook"]:::auto
    S8 --> S9W["Step 9 Wait for container<br/>1-3 minutes"]:::auto
    S9W --> S9U["Step 9 💬 Send 'hi' to bot<br/>share pairing code"]:::user
    S9U --> S9A["Step 9 Approve Telegram pairing"]:::auto
    S9A --> SF["Final ✅ Open Dashboard + Admin"]:::auto
    SF --> SFU["Final ✅ Click Approve<br/>in Admin panel"]:::user
    SFU --> Done["🎉 Your bot is live!"]:::done

    classDef user fill:#ffcdd2,stroke:#c62828,color:#000
    classDef auto fill:#c8e6c9,stroke:#2e7d32,color:#000
    classDef done fill:#bbdefb,stroke:#1565c0,color:#000
```

| | Count | What |
|---|---|---|
| 🔴 **You do** | 6 steps | Create tokens, send "hi", click Approve |
| 🟢 **AI does** | 11 steps | Install, build, deploy, configure, everything else |

## Security architecture

Three zones — Users (left), Cloudflare (middle), Internet (right) — with security at every boundary:

![Security Architecture](diagram.png)

### Security layers explained

| Layer | Protection | Auth mechanism |
|-------|-----------|----------------|
| **1. Cloudflare Edge** | DDoS, WAF, bot protection | Automatic |
| **2. Worker** | Route-level auth | `MOLTBOT_GATEWAY_TOKEN` + CF Access (production) |
| **3. Private Network** | No public IP | Container only reachable from Worker via `10.0.0.1` |
| **4. OpenClaw Gateway** | Dashboard + API access | Token auth + device pairing |
| **5. AI Gateway** | AI request protection | `cf-aig-authorization` token + rate limiting |
| **6. Storage** | Data protection | Private R2 bucket + S3 credentials (per-bucket) |
| **Telegram** | DM access | Pairing policy — only approved users can chat |

### DEV_MODE vs Production

| | DEV_MODE=true (default) | Production (DEV_MODE=false) |
|---|---|---|
| `/_admin/` | Anyone with URL | CF Access SSO required |
| `/debug/*` | Anyone with URL | CF Access SSO required |
| Dashboard | Gateway Token only | CF Access + Gateway Token |
| Telegram | Pairing required | Pairing required |

> **Tip:** For personal use, DEV_MODE=true is fine. For company use, set `DEV_MODE=false` and configure [Cloudflare Zero Trust Access](https://developers.cloudflare.com/cloudflare-one/).

## What gets created on Cloudflare

| Resource | Name | Purpose |
|----------|------|---------|
| Worker | `{name}.{subdomain}.workers.dev` | Entry point — handles auth, routing, container lifecycle |
| Container | (auto-created) | Runs the OpenClaw AI agent |
| AI Gateway | `{name}-gateway` | Logs AI requests, rate limiting, authentication |
| R2 Bucket | `{name}-data` | Persists config, sessions, workspace across restarts |
| Secrets | 14 total | API keys, tokens, URLs, feature flags |

## Quick start

### As an OpenClaw Skill

Copy this folder to your OpenClaw skills directory. Then ask your agent:

> "Deploy a new OpenClaw bot"

### With Claude Code or Claude Desktop

Point the AI to `SKILL.md` and say:

> "Follow the instructions in SKILL.md to deploy a new OpenClaw bot"

### Manual

Read `SKILL.md` for the complete step-by-step commands. Every command is documented — you can run them yourself if needed.

## File structure

```
deploy-openclaw/
├── SKILL.md              ← Instructions for the AI agent (the brain)
├── README.md             ← You are here
└── moltworker/           ← Pre-configured source code (no git clone needed)
    ├── Dockerfile        ← Container: Node 22.16.0 + OpenClaw 2026.3.13
    ├── start-openclaw.sh ← Container startup: onboard + config patch + gateway
    ├── wrangler.jsonc    ← Worker + Container + R2 bindings
    ├── package.json      ← Dependencies
    ├── src/              ← Worker source code (TypeScript)
    ├── skills/           ← Built-in skills (browser automation)
    └── public/           ← Dashboard UI assets (logos)
```

## Key concepts

| Term | What it is |
|------|-----------|
| **OpenClaw** | Open-source AI agent — handles conversations, tools, memory |
| **Moltworker** | Cloudflare Worker that wraps OpenClaw in a container |
| **Worker** | Lightweight JavaScript at the edge — the "front door" |
| **Container** | Full Linux environment — where OpenClaw actually runs |
| **AI Gateway** | Cloudflare proxy for AI requests — adds logging and protection |
| **R2** | Cloudflare object storage — keeps your data when container sleeps |
| **SKILL.md** | Instructions file that AI agents read and execute |

## Versions

| Component | Version |
|-----------|---------|
| OpenClaw | 2026.3.13 |
| Node.js (in container) | 22.16.0 |
| Moltworker | Snapshot 2026-03-25 |
| Container size | standard-2 (2 vCPU, 4GB RAM) |

## Updating

1. Clone latest [cloudflare/moltworker](https://github.com/cloudflare/moltworker)
2. Copy files into `moltworker/` (keep current structure)
3. Re-apply modifications to `start-openclaw.sh` (auth order + allowedOrigins)
4. Update versions in `Dockerfile` if needed
5. Test deploy, then commit + push

## License

Moltworker source code is from [cloudflare/moltworker](https://github.com/cloudflare/moltworker) under its original license.
