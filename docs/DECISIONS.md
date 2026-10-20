

### ADR-014: Deployment layout — one Caddy edge per host, stacks on a shared edge network, local transport for practice
- **Status:** accepted (Phase 2, 20 Oct 2026)
- **Context:** SPEC 3/7: only Caddy publishes ports; one stack per client; practice without a VPS; idempotent deploys.
- **Decision:** Host layout `<opskit_root>/{clients/<id>/{compose.yml,.env},caddy/etc/{Caddyfile,sites/<id>.caddy},caddy/{data,config},agent,logs}`; pinned `caddy:2.10.0` container on Docker network `opskit_edge`; each app joins it with alias `<id>-app`; Postgres/Redis stay private; compose project = client id, no `container_name`, named volumes `<id>_postgres/_redis/_cache`. Secrets generated once per client on the operator machine (`clients/<id>/secrets.env`, 600). Host transport `ssh` (BatchMode, `sudo -n` only for bootstrap) or `local` (practice/selftest) behind `host_run/host_put`.
- **Alternatives:** binding each app to 127.0.0.1:<port> with host-level Caddy (needs port allocation now, shared-host work deferred); Caddy as a systemd service (less reproducible); regenerating secrets per render (would break stored connections).
- **Consequences:** Adding shared hosts later needs no port allocation for apps (only DNS/sites). The edge is a single point per host (restart policy + uptime monitor in Phase 4). Practice hosts may need the IPv4 listen shim (`practice_quirks`), never used on real hosts.
