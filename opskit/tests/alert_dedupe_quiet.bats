#!/usr/bin/env bats

load helpers/common
load helpers/mock_http

setup() {
  ROOT="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme"
  cp "${OPSKIT_ROOT}/agent/alert.sh" "${ROOT}/agent/"
  cp -r "${OPSKIT_ROOT}/templates/alerts" "${ROOT}/agent/alerts"
  ALERT="${ROOT}/agent/alert.sh"
  start_mock_http
  export OPSKIT_TELEGRAM_API="$MOCK_URL"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${ROOT}/agent/alerts.conf"
  printf 'TELEGRAM_CHAT_ID=222\nTIMEZONE=Europe/London\nQUIET_FROM=22:00\nQUIET_TO=07:00\n' > "${ROOT}/clients/acme/alerts.conf"
}

teardown() {
  stop_mock_http
  rm -rf "$ROOT"
}

london() {
  TZ=Europe/London date -d "$1" +%s
}

alert_at() {
  local at="$1" severity="$2"
  shift 2
  OPSKIT_NOW="$at" run "$ALERT" --root "$ROOT" --client acme --severity "$severity" --what "Lead capture failed" --action "open the run" "$@"
}

chats() {
  mock_requests | jq -r .body | jq -r .chat_id | sort | tr '\n' ' '
}

@test "the same key inside the window is sent once" {
  local t
  t="$(london '2026-01-15 12:00')"
  alert_at "$t" critical --dedupe-key flow:f1
  [ "$status" -eq 0 ]
  alert_at "$((t + 29 * 60))" critical --dedupe-key flow:f1
  [ "$status" -eq 0 ]
  [[ "$output" == *"duplicate alert suppressed (30 min window)"* ]]
  [ "$(chats)" = "111 222 " ]
}

@test "after the window the key alerts again" {
  local t
  t="$(london '2026-01-15 12:00')"
  alert_at "$t" critical --dedupe-key flow:f1
  alert_at "$((t + 31 * 60))" critical --dedupe-key flow:f1
  [ "$(mock_requests | jq -s length)" = "4" ]
}

@test "different keys and a custom window are independent" {
  local t
  t="$(london '2026-01-15 12:00')"
  alert_at "$t" critical --dedupe-key flow:f1
  alert_at "$t" critical --dedupe-key flow:f2
  alert_at "$((t + 3 * 60))" critical --dedupe-key flow:f1 --window 2
  [ "$(mock_requests | jq -s length)" = "6" ]
}

@test "when the owner was not reached the key is forgotten so the next run retries" {
  local t
  t="$(london '2026-01-15 12:00')"
  OPSKIT_TELEGRAM_API="http://127.0.0.1:9" alert_at "$t" critical --dedupe-key flow:f1
  [ "$status" -eq 1 ]
  alert_at "$((t + 60))" critical --dedupe-key flow:f1
  [ "$status" -eq 0 ]
  [ "$(chats)" = "111 222 " ]
}

@test "quiet hours hold info/warn for the client but the owner still gets it" {
  alert_at "$(london '2026-01-15 23:30')" warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"quiet hours"* ]]
  [ "$(chats)" = "111 " ]
  [ "$(wc -l < "${ROOT}/state/acme/held.jsonl")" -eq 1 ]
  [ "$(jq -r .severity "${ROOT}/state/acme/held.jsonl")" = "warn" ]
}

@test "critical alerts ignore quiet hours" {
  alert_at "$(london '2026-01-15 23:30')" critical
  [ "$(chats)" = "111 222 " ]
  [ ! -e "${ROOT}/state/acme/held.jsonl" ]
}

@test "quiet hours crossing midnight: 06:59 is quiet, 07:00 is not" {
  alert_at "$(london '2026-01-16 06:59')" info
  [ "$(chats)" = "111 " ]
  alert_at "$(london '2026-01-16 07:00')" info
  [ "$(chats)" = "111 111 222 " ]
}

@test "quiet hours use the client's time zone, including summer time" {
  printf 'TELEGRAM_CHAT_ID=222\nTIMEZONE=America/New_York\nQUIET_FROM=13:00\nQUIET_TO=14:00\n' > "${ROOT}/clients/acme/alerts.conf"
  alert_at "$(TZ=America/New_York date -d '2026-07-01 13:30' +%s)" warn
  [ "$(chats)" = "111 " ]
  alert_at "$(TZ=America/New_York date -d '2026-07-01 14:30' +%s)" warn
  [ "$(chats)" = "111 111 222 " ]
}

@test "--no-quiet and missing quiet hours send to everyone" {
  alert_at "$(london '2026-01-15 23:30')" info --no-quiet
  [ "$(chats)" = "111 222 " ]
  printf 'TELEGRAM_CHAT_ID=222\nTIMEZONE=Europe/London\nQUIET_FROM=\nQUIET_TO=\n' > "${ROOT}/clients/acme/alerts.conf"
  alert_at "$(london '2026-01-15 23:30')" info
  [ "$(chats)" = "111 111 222 222 " ]
}

@test "a bad --window value is rejected" {
  run "$ALERT" --root "$ROOT" --client acme --severity info --what x --action y --dedupe-key k --window soon
  [ "$status" -eq 1 ]
  [ "$(mock_requests | jq -s length)" = "0" ]
}
