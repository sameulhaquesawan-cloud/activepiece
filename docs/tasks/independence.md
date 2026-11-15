# Independence from Activepieces' servers (owner approved 15 Nov 2026: "only ours"; ADR-021)

Owner, 15 Nov 2026: client stacks must keep working whatever Activepieces changes or switches off. CE is MIT, so this is allowed. The EE rule stays (we never touch `packages/ee/` or the EE license).

## What still depends on Activepieces today (checked in the pinned 0.92.3 source)
| # | Dependency | Where | What breaks if it changes |
|---|---|---|---|
| D1 | App image `activepieces/activepieces:<tag>` on Docker Hub/ghcr | `opskit/templates/compose.yml.tmpl` (`AP_IMAGE`) | new deploys, restores and upgrades, if a tag is removed or the registry blocks us |
| D2 | Piece catalog sync from `cloud.activepieces.com` every hour (`AP_PIECES_SYNC_MODE` default `OFFICIAL_AUTO`) | `packages/server/api/src/app/pieces/piece-sync-service.ts` | adds new versions **and deletes official versions no longer on the list** (`deletePiecesIfNotOnCloud`); fresh stacks only get the listed versions (the stale-pin problem) |
| D3 | Piece code from `cdn.activepieces.com/pieces/bundled/`, falling back to `registry.npmjs.org` | `packages/server/api/src/app/pieces/piece-bundle.ts` | runs that need a piece not yet cached on the worker |
| D4 | "OAuth2 (Recommended)" sign-in for Gmail, Sheets, Slack, HubSpot through `secrets.activepieces.com` (claim + refresh) | `cloud-oauth2-service.ts`, web `oauth2-utils.ts` | every such connection stops refreshing its token; Activepieces also sees the tokens (ASSUMPTIONS #17) |
| D5 | Small extras: flow templates (`cloud.activepieces.com/api/v1/templates`), AI model list and logos from `cdn.activepieces.com` | api/web | cosmetic, to be verified |

## Proposed tasks
- [ ] **I.1 Facts (no code)** — source facts done (ASSUMPTIONS #34: npm tarballs carry no dependencies; archive pieces are served from the stack's own file store; the sync never deletes platform pieces). Left: the running-stack facts, proven once the CI selftest (fresh frozen stack + pack install) is green: archive install of an npm piece tarball vs the CDN bundle (does it carry its dependencies, or does the worker still fetch them from npm?); `AP_PIECES_SYNC_MODE=NONE` on a fresh stack (empty catalog? builder still works?); can a platform piece have the same name as an official one (hybrid option); what D5 does offline.
- [x] **I.2 Own image mirror (D1)** — `opskit/image/mirror.yaml`, `opskit/bin/image-mirror`, `mirror` job in `opskit-ci.yml`, `image_mirror.bats`: CI copies each pinned tag (by digest, amd64 + arm64) to our GHCR; `AP_IMAGE` defaults to it; upgrade gate accepts only mirrored tags.
- [x] **I.3 Own piece pack (D2, D3)** — `opskit pieces list|add|check|install`, `opskit/pieces/` (11 pieces; 15 since 15 Nov 2026 with forms, approval, http, telegram-bot), `pieces.catalog` in client.yaml, `pieces.bats`, `pieces_install.bats`: `opskit pieces add` stores the exact piece versions our templates need (+ any the owner adds) as files we own; `opskit pieces install <client>` installs them into the client's stack via CE's own `POST /v1/pieces` (platform pieces are never deleted by the sync). Deploy sets `AP_PIECES_SYNC_MODE=NONE` (frozen catalog, recommended) or keeps the full catalog (hybrid, if I.1 says it is safe).
- **I.4 Own sign-in apps (D4):** templates and guides use "Custom OAuth2 App" with our (or the client's) Google/Slack/HubSpot app; tokens stay on the client's server. Needs the owner's Google Cloud project (2-step verification).
- **I.5 Offline proof:** selftest runs a stack with outbound access to `*.activepieces.com` blocked: deploy, templates import and run, backup/restore and upgrade still pass.

## Open questions for the owner
- **Q1 — Builder catalog:** answered: **only ours**. [Frozen: clients see only the pieces we installed for them (we add more on request, a 2-minute command). Hybrid keeps all 400+ visible, but those can still change under us.]
- **Q2 — Sign-in apps:** [One Google/Slack/HubSpot app owned by your business for all clients (simple). Per-client apps for EU clients that ask.]
- **Q3 — Image mirror visibility:** [Public GHCR package (free, no pull secret on servers); the image is MIT code anyway.]
