# Example — webhook greeting

The smallest template, used by `opskit flows validate` / `import` tests. Not for clients.

**What it does:** a webhook receives `{"name": "…"}`; a code step builds `"<GREETING>, <name>"`. A body
without `name` makes the run fail (so the failed-run alert fires, see `../CONVENTIONS.md`).

**Placeholders:** `GREETING` (default `Hello`).
**Connections:** none.

## Sample run
1. `opskit flows import example <client>` (or import `flow.json` in the builder after filling `GREETING`).
2. Open the flow, publish it, copy the webhook URL.
3. `curl -X POST <webhook url> -H 'content-type: application/json' -d @test/good.json` → run SUCCEEDED,
   step output `Hello, Sam Example`.
4. Same with `test/missing-name.json` → run FAILED at "Check name".
