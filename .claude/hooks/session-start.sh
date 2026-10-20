#!/usr/bin/env bash
# Claude Code cloud sessions only: run the tool-neutral dev setup.
# No-op on the owner's laptop (WSL), where `opskit/bin/dev-env` is run by hand.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

"${CLAUDE_PROJECT_DIR:-.}/opskit/bin/dev-env"
