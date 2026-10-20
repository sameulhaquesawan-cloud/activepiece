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
Any Linux shell: GitHub Codespaces, WSL2 Ubuntu, a VPS, or a cloud AI session.
1. `git clone` the repo (or open it), `git fetch origin` and check out the working branch named in `docs/PROGRESS.md`.
2. `opskit/bin/dev-env` — installs shellcheck, bats, rclone, age, jq, yq and starts Docker if needed (WSL: start Docker Desktop first). Re-runnable.
3. Network the stack needs: Docker Hub (`registry-1.docker.io`) or GHCR (`ghcr.io`, `pkg-containers.githubusercontent.com`), and from **inside containers** `cloud.activepieces.com` (piece catalog, templates) and `registry.npmjs.org` (piece code).
4. Never read or print `.env` files or anything in `opskit/clients/`, `opskit/hosts/`, `explore/` secrets.

## Recreate the Phase 0 explore stack
`explore/` is git-ignored, so a new machine starts empty. Upstream files are copied, never edited.
```bash
mkdir -p explore/stack && cd explore/stack
cp ../../docker-compose.yml ../../.env.example .
bash ../../tools/deploy.sh && chmod 600 .env          # official secret generation
cat > docker-compose.override.yml <<'EOF'
services:
  app:
    environment:
      - AP_CONTAINER_TYPE=APP
      - AP_EDITION=ce
      - AP_FRONTEND_URL=http://localhost:8080
      - AP_TELEMETRY_ENABLED=false
  worker:
    environment:
      - AP_CONTAINER_TYPE=WORKER
      - AP_EDITION=ce
      - AP_FRONTEND_URL=http://app
      - AP_TELEMETRY_ENABLED=false
    deploy:
      replicas: 1
EOF
docker compose -p ap0 up -d
curl -s http://localhost:8080/api/v1/health            # {"status":"Healthy"}
```
Then open `http://localhost:8080` (Codespaces: the Ports tab gives a browser link) and create the admin account.
Quirks seen so far (details in `docs/EXPLORATION_REPORT.md` §1):
- GHCR blocked → use `activepieces/activepieces:<tag>` (Docker Hub, same official image).
- App crash-loops with `listen EAFNOSUPPORT :::80` only on kernels without IPv6 → explore-only `NODE_OPTIONS=--require` shim mapping `::` to `0.0.0.0`.
- Empty piece list → containers can't reach `cloud.activepieces.com`.

## Keep the handoff working
- At the end of every task, update `docs/PROGRESS.md`: Current status, a dated Task log entry, and **Next steps** precise enough for a stranger to continue.
- Commit + push after every task (conventional commits); nothing important may live only in a chat or in `explore/`.
- Decisions go to `docs/DECISIONS.md` / `docs/ASSUMPTIONS.md`, never only in chat.
