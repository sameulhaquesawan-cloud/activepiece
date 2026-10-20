# Environment & Setup — Automation Ops Kit

> Derived from `docs/SPEC.md` Sections 4, 16. If this conflicts with SPEC, SPEC wins.

## 1. Laptop tooling (all work happens in WSL2 Ubuntu)
| Tool | Notes |
|---|---|
| Windows 10/11 + WSL2 Ubuntu 24.04 | `wsl --install -d Ubuntu-24.04` |
| Docker Desktop (WSL2 backend, WSL integration on) | Compose v2 (`docker compose version`) |
| VS Code + Remote-WSL | Open the repo from WSL so the IDE agent runs Bash |
| Claude Code (cloud session at claude.ai/code, or CLI in WSL) | Cloud sessions get tools + Docker from `.claude/hooks/session-start.sh` |
| git, openssl, jq, yq, curl, gettext (envsubst), shellcheck, bats, age, rclone, ssh | `opskit doctor` checks all |
| Node + bun per upstream `.nvmrc`/docs | Only for custom pieces and upstream dev (Phase 0/8) |
| ngrok (free) | Local webhook testing only |

## 2. Accounts (free unless noted)
GitHub (fork, Actions, GHCR) · Telegram bot via @BotFather (demo alerts) · Gemini API key (free tier, practice data only) · ngrok free · UptimeRobot free · Backblaze B2 (10 GB free) or other rclone remote · VPS provider (paid, per client) · domain (owner + clients) · Oracle Cloud (optional, practice).

## 3. Opskit variables (per client, in `client.yaml`; secrets in host `.env` only)
| Name | Where | How to get |
|---|---|---|
| `AP_ENCRYPTION_KEY`, `AP_JWT_SECRET`, `AP_POSTGRES_PASSWORD` | generated into host `.env` | `opskit render` (openssl rand; aborts if empty) |
| `AP_FRONTEND_URL` | `.env` (app) / compose (worker = `http://app`) | domain from `client.yaml` |
| `AP_EDITION=ce` | `.env` | fixed (verify exact value) |
| `OPSKIT_HUB_URL`, `OPSKIT_HUB_TOKEN` | host agent config | ops-hub alert-router webhook |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | ops-hub connections | @BotFather; chat id via getUpdates |
| SMTP host/user/pass | ops-hub connection | provider (e.g. Brevo/Gmail app password) |
| Slack webhook URL | ops-hub connection | Slack app → Incoming Webhooks |
| WhatsApp Cloud API token + phone id | ops-hub connection (client) | Meta developer app (client-provided) |
| rclone remote | host | `rclone config` (B2 key id/app key) |
| age public key | repo `opskit/keys/owner.age.pub` (public only) | `age-keygen`; private key offline |

## 4. Rules
- Never commit `.env`, private keys, `opskit/clients/`, dumps, IPs of client hosts.
- Keep the age private key and each client's `AP_ENCRYPTION_KEY` recoverable (password manager + escrow).
- Use Gemini free tier only with practice data; client AI steps use the client's own paid keys.
