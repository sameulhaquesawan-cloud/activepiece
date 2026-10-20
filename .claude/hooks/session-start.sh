#!/usr/bin/env bash
# Prepares a Claude Code cloud session for opskit work: ops tools + Docker daemon.
# No-op on the owner's laptop (WSL), where these are installed by hand.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

missing=()
for tool in shellcheck bats rclone age jq yq; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
  sudo apt-get update -qq >/dev/null
  sudo apt-get install -y -qq "${missing[@]}" >/dev/null
fi

if ! docker info >/dev/null 2>&1; then
  sudo sh -c 'nohup dockerd >/var/log/dockerd.log 2>&1 &'
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 1
  done
fi

docker info >/dev/null 2>&1 && echo "[ok] docker daemon running" || echo "[warn] docker daemon not running"
