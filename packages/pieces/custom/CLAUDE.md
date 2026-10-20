# packages/pieces/custom — our custom pieces

- Follow upstream piece conventions (see upstream AGENTS.md/docs) and the "Custom pieces & flow template rules" in `.claude/CLAUDE.md`.
- Tests for every action/trigger; auth via piece props; no secrets in code.
- Own image is V2. `openai-compatible` (ADR-013) ships as an archive installed via the CE admin API (`POST /api/v1/pieces`, `packageType: ARCHIVE`).
