# OpenAI Compatible (BYOK) — `@opskit/piece-openai-compatible`

Use any OpenAI-compatible endpoint (OpenAI, OpenRouter, Groq, DeepSeek, Together, Ollama, LM Studio, vLLM, …) with your own key. ADR-013.

- **Connection:** Base URL (e.g. `https://api.openai.com/v1`) + API key (optional for local servers). Stored encrypted by Activepieces (`AP_ENCRYPTION_KEY`); never in git or `.env`.
- **Ask Model:** model dropdown loaded live from `{baseUrl}/models`; `reasoning_effort` **high** by default (xhigh/medium/low/minimal/none, "Don't send", custom); system prompt; max output tokens (`max_completion_tokens` or `max_tokens`); temperature; extra JSON fields. Output: `text`, `reasoning`, `model`, `finishReason`, `usage`.
- **List Models** and **Custom API Call** actions.

## Develop
```bash
bun install --filter '@opskit/piece-openai-compatible' --filter '@activepieces/cli'   # full install fails on a blocked GitHub tarball
cd packages/pieces/custom/openai-compatible && npx vitest run && npx eslint 'src/**/*.ts'
git checkout -- bun.lock   # keep the upstream lockfile untouched (fork check)
```

## Build the archive
```bash
TS_NODE_TRANSPILE_ONLY=true npm run cli -- pieces build openai-compatible
# → packages/pieces/custom/openai-compatible/dist/opskit-piece-openai-compatible-<version>.tgz (self-contained, no deps)
git checkout -- bun.lock
```
`TS_NODE_TRANSPILE_ONLY` skips an upstream type error in `packages/core/utils` that only the CLI's ts-node trips on.

## Install into a Community Edition stack (no own image)
Platform admin token (`POST /api/v1/authentication/sign-in` → `token`), then:
```bash
curl -H "authorization: Bearer $TOKEN" \
  -F packageType=ARCHIVE -F scope=PLATFORM \
  --form-string pieceName=@opskit/piece-openai-compatible -F pieceVersion=<version> \
  -F "pieceArchive=@dist/opskit-piece-openai-compatible-<version>.tgz;type=application/gzip" \
  https://<domain>/api/v1/pieces
```
Bump `version` in `package.json` for every change; installed per stack (re-install after upgrades).

## Verified (0.92.3, 20 Oct 2026)
Installed via archive on a CE stack; connection to `https://openrouter.ai/api/v1` without key validated; model dropdown listed 468 live models in ~1 s; a run without key failed with "The API key was rejected…" (as designed). Not yet verified: a successful completion with a real key (owner).
