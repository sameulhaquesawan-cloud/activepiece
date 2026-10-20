# Handoff — continue this project in any session or with any AI

Works for Claude Code, Codex, Cursor, Kilo, Gemini, Copilot or a human. Nothing here needs Claude.

## Prompt to paste into a new chat
> This repo is my Activepieces fork + "opskit". Read `README-START-HERE.md`, then `docs/HANDOFF.md`, and follow them. Continue from "Next steps" in `docs/PROGRESS.md`. Work on the git branch named there, commit and push after each task. I'm semi-technical: when I must do something, give me short numbered steps.

## Read in this order
1. `docs/HANDOFF.md` (this file).
2. `.claude/CLAUDE.md` — **the working rules for every AI**, not only Claude (the folder name is historical). Rules there win over your own defaults.
3. `docs/PROGRESS.md` — current phase, task, **Next steps**, Known issues.
4. `docs/tasks/phase-N.md` for the current phase (if it exists), then only the `docs/SPEC.md` sections it points to.
5. Procedures: `.agents/skills/opskit-*/SKILL.md` are plain Markdown checklists. Without slash commands, just "do what `.agents/skills/opskit-next-task/SKILL.md` says".

## Set up the machine
Any Linux shell: GitHub Codespaces (current choice), WSL2 Ubuntu on the laptop (later), a VPS, or a cloud AI session.

### Option A — GitHub Codespaces (in the browser, nothing to install)
1. Open the repo on github.com and pick the working branch (see `docs/PROGRESS.md`) in the branch dropdown.
2. Green **Code** button → **Codespaces** tab → **⋯** → **New with options**.
3. **Dev container configuration:** `opskit (Activepieces CE explore + ops tooling)` — not "Activepieces Dev", which builds the whole source and burns free hours. **Machine type:** 2-core is enough (4-core for piece development). **Create codespace**.
4. Wait for setup (first time: several minutes). It installs the tools and starts Activepieces by itself. Then **Ports** tab → port **8080 "Activepieces"** → globe icon opens it in your browser.
5. To have an AI work in it: open the terminal (bottom panel), start your AI tool there (e.g. `npm install -g @anthropic-ai/claude-code && claude`), paste the prompt above.
6. When done: github.com/codespaces → **⋯** → **Stop codespace** (it also stops by itself after ~30 min idle). A stopped codespace keeps files and data; deleting it loses `explore/`.

### Option B — Windows laptop (WSL2)
Needs: Windows 11 or Windows 10 22H2 (64-bit, updated) · virtualization on in BIOS (usually already) · 12 GB RAM is fine (Activepieces idle ≈ 0.8 GB; close heavy apps) · ≥ 30 GB free disk · internet. All software free: WSL2 + Ubuntu 24.04 (`wsl --install -d Ubuntu-24.04` in PowerShell as admin), Docker Desktop (WSL2 backend, WSL integration on; free for personal use and small businesses), optional VS Code + "WSL" extension, any AI tool. Clone the repo **inside Ubuntu** (e.g. `~/work/`), not on the Windows C: drive.

### Then, on any machine
1. `git clone` the repo (Codespaces: already done), `git fetch origin` and check out the working branch named in `docs/PROGRESS.md`.
2. `opskit/bin/dev-env` — installs shellcheck, bats, rclone, age, jq, yq and starts Docker if needed (WSL: start Docker Desktop first). Re-runnable.
3. Network the stack needs: Docker Hub (`registry-1.docker.io`) or GHCR (`ghcr.io`, `pkg-containers.githubusercontent.com`), and from **inside containers** `cloud.activepieces.com` (piece catalog, templates) and `registry.npmjs.org` (piece code).
4. Never read or print `.env` files or anything in `opskit/clients/`, `opskit/hosts/`, `explore/` secrets.

## Run the Phase 0 explore stack
`explore/` is git-ignored, so a new machine starts empty. One command creates it (official `tools/deploy.sh` secrets, CE, 1 worker, worker URL fix, telemetry off) and starts it:
```bash
opskit/bin/explore-stack up       # also: status, stop (data kept)
```
Then open `http://localhost:8080` (Codespaces: Ports tab) and create the admin account. Upstream files are copied, never edited. The script handles two quirks by itself: GHCR unreachable → same official image from Docker Hub; kernel without IPv6 (`listen EAFNOSUPPORT :::80`) → explore-only IPv4 shim. If the piece list is empty, the containers can't reach `cloud.activepieces.com`.

## Keep the handoff working
- At the end of every task, update `docs/PROGRESS.md`: Current status, a dated Task log entry, and **Next steps** precise enough for a stranger to continue.
- Commit + push after every task (conventional commits); nothing important may live only in a chat or in `explore/`.
- Decisions go to `docs/DECISIONS.md` / `docs/ASSUMPTIONS.md`, never only in chat.
