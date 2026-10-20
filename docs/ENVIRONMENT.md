# Environment & Setup — Automation Ops Kit

> Derived from `docs/SPEC.md` Sections 4, 16. If this conflicts with SPEC, SPEC wins.

## 1. Machines
Current: GitHub Codespaces with `.devcontainer/opskit/devcontainer.json` (free monthly quota). Later: the laptop. Requirements and steps for both: `docs/HANDOFF.md`. Any machine: run `opskit/bin/dev-env`.

### Laptop tooling (all work happens in WSL2 Ubuntu)
| Tool | Notes |
|---|---|
| Windows 10/11 + WSL2 Ubuntu 24.04 | `wsl --install -d Ubuntu-24.04` |
| Docker Desktop (WSL2 backend, WSL integration on) | Compose v2 (`docker compose version`) |
| VS Code + Remote-WSL | Open the repo from WSL so the IDE agent runs Bash |
| Any AI tool (Claude Code, Codex, Cursor, …) | Claude cloud sessions run `opskit/bin/dev-env` via `.claude/hooks/session-start.sh` |
| git, openssl, jq, yq **v4 (mikefarah)**, curl, gettext (envsubst), shellcheck, bats, age, rclone, ssh | `opskit/bin/dev-env` installs them; `opskit doctor` checks all |
| Node + npx (operator machine) | `opskit validate` runs pinned `ajv-cli` via npx (first use needs network) |
| Node + bun per upstream `.nvmrc`/docs | Only for upstream dev and V2 custom pieces |

## 2. Accounts (free unless noted)
GitHub (fork, Actions, GHCR) · Telegram bot via @BotFather (demo alerts) · Gemini API key (free tier, practice data only) · UptimeRobot free · Backblaze B2 (10 GB free) or other rclone remote · VPS provider (paid, per client) · domain (owner + clients) · Oracle Cloud (optional, practice).

## 3. Opskit variables (per client, in `client.yaml`; secrets in host `.env` only)
| Name | Where | How to get |
|---|---|---|
| `AP_API_KEY`, `AP_ENCRYPTION_KEY`, `AP_JWT_SECRET`, `AP_POSTGRES_PASSWORD` | generated into host `.env` | `opskit render` (openssl rand; aborts if empty) |
| `AP_FRONTEND_URL` | `.env` (app) / compose (worker = `http://app`) | domain from `client.yaml` |
| `AP_EDITION=ce`, `AP_TELEMETRY_ENABLED=false` | `.env` | fixed (verified 0.92.3) |
| `OPSKIT_KUMA_PUSH_URL` | host agent config | Uptime Kuma push monitor URL per client |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | host agent config (secret, mode 600) | @BotFather; chat id via getUpdates |
| SMTP host/user/pass | host msmtp config (secret, mode 600) | provider (e.g. Brevo/Gmail app password) |
| Slack webhook URL | host agent config (secret) | Slack app → Incoming Webhooks |
| rclone remote | host | `rclone config` (B2 key id/app key) |
| age public key | repo `opskit/keys/owner.age.pub` (public only) | `age-keygen`; private key offline |
| `OPSKIT_OWNER_AGE_KEY` | operator machine only (restore, restore-test) | path to the age **private** key; default `~/.config/opskit/owner.key` (mode 600); never on hosts, never in git |
| `OPSKIT_OWNER_AGE_PUB` | operator machine (deploy) | override for the public key path (tests/selftest) |
| owner channels / rclone | `opskit/owner/alerts.conf`, `opskit/owner/rclone.conf` (git-ignored, 600) | copied to each host's `agent/` by `opskit deploy` |
| owner email (SMTP) | `opskit/owner/alerts.conf`: `SMTP_URL` (e.g. `smtp://smtp-relay.brevo.com:587`), `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, optional `SMTP_TLS` (`starttls` default; `none` only for a local test relay), optional `OWNER_EMAIL` | SMTP provider (Brevo free / Gmail app password); sent with `curl`, no msmtp |

## 4. Rules
- Never commit `.env`, private keys, `opskit/clients/`, dumps, IPs of client hosts.
- Keep the age private key and each client's `AP_ENCRYPTION_KEY` recoverable (password manager + escrow).
- Use Gemini free tier only with practice data; client AI steps use the client's own paid keys.
