---
name: oc-on-cf
description: Deploy OpenClaw on Cloudflare using the `/deploy-openclaw` command. Includes the bundled `moltworker/` project and browser skill assets needed for deployment.
---

# OC on CF Skill

This skill packages the OpenClaw-on-Cloudflare deployment workflow for agent installation.

## Primary Command

- `/deploy-openclaw`

## What It Includes

- `moltworker/` — pre-configured Cloudflare Worker + container project
- `commands/deploy-openclaw.md` — full deployment workflow
- `moltworker/skills/cloudflare-browser/` — bundled browser automation skill

## Purpose

Use this skill when you want an agent to deploy a new OpenClaw bot to Cloudflare Workers + Containers, including Telegram setup and dashboard pairing.

## Notes

- The full deployment instructions live in `commands/deploy-openclaw.md`.
- The bundled source code lives under `moltworker/`, so no separate git clone is needed during deployment.
