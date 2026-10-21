# Shared fixtures for the upgrade tests: demo client acme on 0.91.4 with a fake host root, a mock
# registry and release notes, a fresh off-server backup and a passed restore test.

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

upgrade_setup() {
  make_registry
  new_demo_client acme acme.example.com
  yq -i '.image.tag = "0.91.4" | .backup.remote = "offsite:acme"' "${REG}/clients/acme/client.yaml"
  HOSTROOT="$(mktemp -d)"
  yq -i ".opskit_root = \"${HOSTROOT}\"" "${REG}/hosts/local-practice.yaml"
  export OPSKIT_UPGRADE_HOST_MIN_FREE_MB=1 OPSKIT_UPGRADE_LOCAL_MIN_FREE_MB=1
  export OPSKIT_OWNER_AGE_KEY="${REG}/owner.key"
  touch "$OPSKIT_OWNER_AGE_KEY"
  export MOCK_RESPONSES="${REG}/responses.json"
  responses '.'
  start_mock_http
  export OPSKIT_GHCR_URL="$MOCK_URL" OPSKIT_UPSTREAM_RAW_URL="$MOCK_URL"
  backup_at "$(date -u +%Y%m%dT%H%M%SZ)" ok
  restore_test pass "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

upgrade_teardown() {
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
