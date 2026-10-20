# opskit — operations kit (our code)

- Follow the Architecture, Ops script and Reliability rules in `.claude/CLAUDE.md`.
- `bin/` entry points; `lib/` shared Bash functions; `schema/` JSON schemas; `templates/` render sources; `agent/` standalone host scripts; `flows/` templates; `hub/` Uptime Kuma notes (+ demo-only ops-hub); `tests/` bats.
- `clients/` and `hosts/` are git-ignored registries with real data — never print their secrets, never commit them.
- Every command validates `client.yaml` first and exits non-zero on failure.
