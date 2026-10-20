#!/usr/bin/env bats

load helpers/common
load helpers/mock_http
load helpers/backup_stubs

setup() {
  make_backup_host
  start_mock_http
  printf 'WEBHOOK_URL=%s/owner-hook\n' "$MOCK_URL" > "${ROOT}/agent/alerts.conf"
  REMOTE_DIR="$(mktemp -d)"
  printf '[offsite]\ntype = local\n' > "${ROOT}/agent/rclone.conf"
}

teardown() {
  stop_mock_http
  rm -rf "$ROOT" "$STUB" "$REMOTE_DIR"
}

configure_backup() {
  printf 'BACKUP_REMOTE=offsite:%s\nHEARTBEAT_URL=%s/api/push/abc123\n' "$REMOTE_DIR" "$MOCK_URL" > "${ROOT}/clients/acme/backup.conf"
}

@test "complete backup sends one heartbeat and no alert" {
  configure_backup
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(mock_requests | jq -s 'length')" = "1" ]
  [ "$(mock_requests | jq -r .method)" = "GET" ]
  mock_requests | jq -r .path | grep -q '^/api/push/abc123?status=up&msg=backup'
}

@test "failed backup sends exactly one critical alert and no heartbeat" {
  configure_backup
  FAKE_PG_DOWN=1 run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [ "$(mock_requests | jq -s 'length')" = "1" ]
  local body
  body="$(mock_requests | jq -r .body)"
  [ "$(jq -r .client <<< "$body")" = "acme" ]
  [ "$(jq -r .severity <<< "$body")" = "critical" ]
  [[ "$(jq -r .what <<< "$body")" == *"Backup of acme failed"* ]]
  [[ "$(jq -r .first_action <<< "$body")" == *"agent/backup.sh acme"* ]]
  ! grep -q 0123456789abcdef "${MOCK_DIR}/requests.jsonl"
}

@test "local-only backup sends a warning" {
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 2 ]
  [ "$(mock_requests | jq -r .body | jq -r .severity)" = "warn" ]
}

@test "telegram alerts go to the owner and the client chat" {
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${ROOT}/agent/alerts.conf"
  printf 'TELEGRAM_CHAT_ID=222\n' > "${ROOT}/clients/acme/alerts.conf"
  OPSKIT_TELEGRAM_API="$MOCK_URL" FAKE_PG_DOWN=1 run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [ "$(mock_requests | jq -r .path | sort -u)" = "/bot123:abc/sendMessage" ]
  [ "$(mock_requests | jq -r .body | jq -r .chat_id | sort | tr '\n' ' ')" = "111 222 " ]
  mock_requests | jq -r .body | jq -r .text | grep -q '^\[CRITICAL\] acme on '
}

@test "alert texts are cut to 300 characters" {
  run "${ROOT}/agent/alert.sh" --root "$ROOT" --client acme --severity info --what "$(printf 'x%.0s' {1..1000})" --action fix
  [ "$status" -eq 0 ]
  [ "$(mock_requests | jq -r .body | jq -r '.what | length')" = "300" ]
}

@test "no owner channel: alert is only logged and reported as undelivered" {
  rm "${ROOT}/agent/alerts.conf"
  run "${ROOT}/agent/alert.sh" --root "$ROOT" --client acme --severity warn --what test --action none
  [ "$status" -eq 1 ]
  [[ "$output" == *"no owner alert channel configured"* ]]
}
