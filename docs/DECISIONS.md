

### ADR-013: One custom piece in V1 — `openai-compatible`, installed by archive (no own image)
- **Status:** accepted (owner, 20 Oct 2026); narrows ADR-012 for this one piece
- **Context:** Owner wants BYOK OpenAI-compatible AI with a live model dropdown and max reasoning by default. CE 0.92.3 has a `custom` AI provider (Platform Admin → AI Center) but its models are typed in by hand (`listModels` returns the stored list) and AI steps send no reasoning effort except `minimal` for OpenAI summaries.
- **Decision:** Build `packages/pieces/custom/openai-compatible` (connection = base URL + API key; dropdown from `GET {baseUrl}/models`; `reasoning_effort` default `high`). Ship it with the CE admin piece-install API (archive), not an own Docker image.
- **Alternatives:** Patch upstream AI provider/worker/web (needs our own image = V2, large ledger); use the built-in custom provider as is (no live models, no reasoning control).
- **Consequences:** Clients keep official images; the piece must be re-installed per stack (scriptable later) and re-tested on upgrades. Built-in AI steps/agents don't use it — flows use the piece's actions.
