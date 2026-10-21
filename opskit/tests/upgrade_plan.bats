#!/usr/bin/env bats

load helpers/common
load helpers/mock_http
load helpers/registry

NOTES='---
title: "Breaking Changes"
---

## Unreleased

### What has changed?

#### Something new that may ship

#### What you need to do

Nothing.

## 0.92.0

#### The old widget endpoint is removed

#### What you need to do

Update callers.

## 0.91.0

#### Already behind us
'

setup() {
  make_registry
  new_demo_client acme acme.example.com
  yq -i '.image.tag = "0.91.4" | .backup.remote = "offsite:acme"' "${REG}/clients/acme/client.yaml"
  HOSTROOT="$(mktemp -d)"
  yq -i ".opskit_root = \"${HOSTROOT}\"" "${REG}/hosts/local-practice.yaml"
  export OPSKIT_UPGRADE_HOST_MIN_FREE_MB=1 OPSKIT_UPGRADE_LOCAL_MIN_FREE_MB=1
  export MOCK_RESPONSES="${REG}/responses.json"
  responses '.'
  start_mock_http
  export OPSKIT_GHCR_URL="$MOCK_URL" OPSKIT_UPSTREAM_RAW_URL="$MOCK_URL"
  backup_at "$(date -u +%Y%m%dT%H%M%SZ)" ok
  restore_test pass "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

teardown() {
  stop_mock_http
  rm -rf "$REG" "$HOSTROOT"
}

responses() {
  jq -n --arg notes "$NOTES" '{
    "GET /token?*": {body: {token: "t"}},
    "GET /v2/activepieces/activepieces/manifests/0.92.3": {body: {schemaVersion: 2}},
    "GET /0.92.3/docs/install/reference/breaking-changes.mdx": {body: $notes}
  } | '"$1" > "$MOCK_RESPONSES"
}

# backup_at <UTC name> <remote state>
backup_at() {
  mkdir -p "${HOSTROOT}/backups/acme/$1"
  printf '{"client":"acme","backup":"%s","db_bytes":10,"env_bytes":5,"encrypted":true,"local":"ok","remote":"%s"}\n' "$1" "$2" \
    > "${HOSTROOT}/backups/acme/$1/status.json"
}

restore_test() {
  printf '{"at":"%s","backup":"x","result":"%s","seconds":60}\n' "$2" "$1" >> "${REG}/clients/acme/restore-tests.jsonl"
}

plan() {
  run "$OPSKIT" upgrade acme --to "${1:-0.92.3}" --plan
}

@test "a plan with every gate green lists the notes and changes nothing" {
  local before
  before="$(sha256sum "${REG}/clients/acme/client.yaml")"
  plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"Upgrade plan for acme: 0.91.4 → 0.92.3 (ghcr.io/activepieces/activepieces)"* ]]
  [[ "$output" == *"[ok] image ghcr.io/activepieces/activepieces:0.92.3 is published"* ]]
  [[ "$output" == *"  0.92.0: The old widget endpoint is removed"* ]]
  [[ "$output" == *"  Unreleased: Something new that may ship"* ]]
  [[ "$output" == *'items under "Unreleased"'* ]]
  [[ "$output" != *"Already behind us"* ]]
  [[ "$output" != *"What you need to do"* ]]
  [[ "$output" == *"[ok] latest backup "*"(0 h old), off-server copy ok"* ]]
  [[ "$output" == *"[ok] last restore test passed"* ]]
  [[ "$output" == *"Plan only: nothing was changed."* ]]
  [ "$(sha256sum "${REG}/clients/acme/client.yaml")" = "$before" ]
}

@test "only newer x.y.z releases are accepted" {
  plan 0.91.4
  [ "$status" -eq 1 ]
  [[ "$output" == *"target 0.91.4 is not newer than the running 0.91.4"* ]]
  plan 0.90.1
  [ "$status" -eq 1 ]
  plan latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"target latest is not a release version"* ]]
}

@test "an unpublished tag and an unreachable registry fail" {
  responses '."GET /v2/activepieces/activepieces/manifests/0.92.3" = {status: 404, body: {}}'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] image ghcr.io/activepieces/activepieces:0.92.3 does not exist"* ]]
  responses 'del(."GET /token?*")'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not reach the registry"* ]]
}

@test "missing release notes are a warning, not a failure" {
  responses 'del(."GET /0.92.3/docs/install/reference/breaking-changes.mdx")'
  plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] could not read 0.92.3's breaking-change notes"* ]]
}

@test "no backup, an old backup or one not off-server stops the upgrade" {
  rm -rf "${HOSTROOT}/backups"
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] no backup of acme"* ]]
  backup_at 20200101T000000Z ok
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"latest backup 20200101T000000Z is older than 26 h"* ]]
  backup_at "$(date -u +%Y%m%dT%H%M%SZ)" failed
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not off-server (remote: failed)"* ]]
}

@test "no restore test, a failed one or an old one stops the upgrade" {
  rm -f "${REG}/clients/acme/restore-tests.jsonl"
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"acme has no restore test yet"* ]]
  restore_test fail "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed: fix it before upgrading"* ]]
  restore_test pass 2020-01-01T00:00:00Z
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"days old (max 35)"* ]]
}

@test "too little disk on the host stops the upgrade" {
  OPSKIT_UPGRADE_HOST_MIN_FREE_MB=999999999 plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"MB free disk (need 999999999 MB"* ]]
}

@test "too little memory on the host stops the upgrade" {
  OPSKIT_UPGRADE_HOST_MIN_MEM_MB=999999999 plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"MB memory available (need 999999999 MB"* ]]
}

@test "an image repo other than the official ones is refused" {
  yq -i '.image.repo = "example.com/activepieces"' "${REG}/clients/acme/client.yaml"
  plan
  [ "$status" -eq 1 ]
  [[ "$output" != *"Upgrade plan for acme"* ]]
}

# bats test_tags=docker
@test "with both images present the plan counts new migrations and names those that cannot be undone" {
  local tag
  for tag in 0.91.4 0.92.3; do
    docker image inspect "ghcr.io/activepieces/activepieces:${tag}" >/dev/null 2>&1 \
      || docker pull -q "ghcr.io/activepieces/activepieces:${tag}" >/dev/null
  done
  plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"Database: 11 new migration(s) in 0.92.3"* ]]
  [[ "$output" == *"[warn] 1 of them cannot be undone by Activepieces (NullOrphanFolderReferences1846000000000)"* ]]
}

@test "without --plan the upgrade refuses for now; usage errors" {
  run "$OPSKIT" upgrade acme --to 0.92.3
  [ "$status" -eq 1 ]
  [[ "$output" == *"use --plan"* ]]
  run "$OPSKIT" upgrade acme --plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit upgrade"* ]]
  run "$OPSKIT" upgrade nobody --to 0.92.3 --plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown client: nobody"* ]]
}
