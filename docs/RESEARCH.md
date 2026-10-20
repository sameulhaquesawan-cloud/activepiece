# Research — Automation Ops Kit (Activepieces fork), 27 September 2026

> Background for `docs/SPEC.md`; not requirements. If anything conflicts with SPEC, SPEC wins. Prices and features change — re-check before quoting.

## 1. Activepieces today
- Community Edition is MIT; enterprise features are under a commercial license in `packages/ee`. Repo: TypeScript monorepo (bun, turbo), ~23k stars; ships its own `AGENTS.md`/`CLAUDE.md`; pieces are TypeScript npm packages with local hot reload.
  Source: https://github.com/activepieces/activepieces
- CE vs paid (sources vary): CE self-hosted has unlimited flows/runs; projects, SSO, roles, audit logs, branding, Git Sync, secret managers and possibly API access/agents are paid.
  Sources: https://noderidge.com/activepieces-review-small-business-automation-2026/ · https://workflowautomation.net/reviews/activepieces
- Cloud pricing moved to per active flow in 2026 (free up to 10 active flows, then ~$5/flow/month).
  Sources: https://automationatlas.io/answers/activepieces-pricing-explained-2026/ · https://blocksentient.com/review/activepieces/

## 2. Install facts (official docs)
- One-command installer `curl -fsSL https://get.activepieces.com | sh` (Compose v2; ≥ 2 vCPU / 4 GB RAM; on Windows run inside WSL2). Manual path: clone, `sh tools/deploy.sh` (needs openssl; silently leaves blanks otherwise), compose up.
- Manual path suggests `AP_EDITION=ee` + `AP_EXECUTION_MODE=SANDBOX_CODE_ONLY` (without it you get Community edition). Worker needs its own `AP_FRONTEND_URL=http://app`; default `replicas: 5` is too many for small machines.
- Four containers: app (8080), worker, postgres, redis. Data lives in the `postgres_data` volume; back up `.env` — without `AP_ENCRYPTION_KEY` stored connections can't be decrypted even from a full DB backup.
- Upgrade: back up with pg_dump, re-run installer with `--upgrade`; version pinned in `AP_VERSION`; read breaking changes first. ngrok for local webhooks, not production.
  Source: https://www.activepieces.com/docs/install/options/docker-compose
- Private piece upload (tarball) and piece management are paid features; the documented custom-piece route assumes a private fork.
  Sources: https://www.activepieces.com/docs/developers/sharing-pieces/private · https://www.activepieces.com/docs/admin-guide/guides/manage-pieces
- Community examples install custom pieces by npm package name on self-hosted instances (method on CE to verify).
  Source: https://github.com/gitmoot/gitmoot-pieces

## 3. Hosting options
- Activepieces image is multi-arch (arm64); one reported Oracle Ampere issue with the Postgres container not receiving env vars.
  Source: https://github.com/activepieces/activepieces/issues/8993
- Oracle Always Free: up to 4 Ampere cores / 24 GB RAM; "out of capacity" is common; free compute must be in the home region.
  Sources: https://oneuptime.com/blog/post/2026-02-08-how-to-set-up-docker-on-an-oracle-cloud-free-tier-instance/view · https://www.itechguides.com/oracle-cloud-giving-away-ampere-arm-a1-instances-always-free-the-2026-limits-explained/

## 4. Market & licensing context
- n8n (Sustainable Use License): helping clients set up their own instances needs no commercial license, but hosting and managing clients' workflows/credentials in your instance requires an Enterprise license.
  Sources: https://vixi.agency/blog/n8n-commercial-license-agencies · https://docs.n8n.io/privacy-and-security/sustainable-use-license
- Upwork n8n specialists bill ~$40–100/hr in 2026.
  Source: https://ciphernutz.com/blog/hire-n8n-expert-cost-pricing-guide

## 5. Factory Droid (for the Factory package)
- AGENTS.md is always-on; Droid searches from cwd to git root and also reads context dirs `.factory/`, `.agents/`, `.agent/`; nested files refine for subtrees; ~80k char initial budget.
  Source: https://docs.factory.ai/harness/agents-md.md
- Skills in `.factory/skills/<name>/SKILL.md` work as `/slash` commands and are auto-invoked; `.factory/commands/*.md` still work; custom droids in `.factory/droids/`.
  Sources: https://docs.factory.ai/harness/skills.md · https://docs.factory.ai/harness/custom-slash-commands.md · https://docs.factory.ai/harness/subagents
