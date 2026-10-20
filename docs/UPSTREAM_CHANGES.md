# Upstream pin & patch ledger

| Field | Value |
|---|---|
| Upstream | https://github.com/activepieces/activepieces |
| Pinned release tag | 0.92.3 |
| Tag SHA | 2fc7f8dcaa84400f9db53fb0de7fc4340d055c62 (released 2026-10-12) |
| Pinned on | 2026-10-20 (merged into our history with `--allow-unrelated-histories`) |

## Patch ledger (changes to upstream files — approval required)
| # | Date | Upstream file(s) | Why | Change summary | Re-apply steps | Test | Status |
|---|---|---|---|---|---|---|---|
| 1 | 2026-10-20 | `.claude/settings.json` | Cloud sessions need Docker + ops tools at start (ADR-011) | Added `hooks.SessionStart` → `.claude/hooks/session-start.sh`; nothing else touched | Re-add the `hooks` block after upstream sync | `jq . .claude/settings.json`; new session prints `[ok] docker daemon running` | owner-requested setup (20 Oct 2026) |
| 2 | 2026-10-20 | `.claude/settings.json` | Owner decision A3: don't auto-enable third-party Claude plugins/MCP from personal repos | `enabledPlugins` `ponytail@ponytail` and `craftspace@craftspace` set to `false`; `mcpServers.context7` removed; marketplaces and other keys untouched | After upstream sync: set both plugins `false`, delete `mcpServers` | `jq -e '.enabledPlugins["ponytail@ponytail"]==false and .enabledPlugins["craftspace@craftspace"]==false and (has("mcpServers")\|not)' .claude/settings.json` | owner-approved (A3, 20 Oct 2026) |
