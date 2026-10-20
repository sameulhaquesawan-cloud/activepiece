#!/usr/bin/env bats

load helpers/common
load helpers/mock_http

setup() {
  ROOT="$(mktemp -d)"
  STUB="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme" "${ROOT}/state/acme/health"
  cp "${OPSKIT_ROOT}/agent/alert.sh" "${OPSKIT_ROOT}/agent/digest.sh" "${ROOT}/agent/"
  cp -r "${OPSKIT_ROOT}/templates/alerts" "${ROOT}/agent/alerts"
  DIGEST="${ROOT}/agent/digest.sh"
  start_mock_http
  export OPSKIT_TELEGRAM_API="$MOCK_URL"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${ROOT}/agent/alerts.conf"
  printf 'TELEGRAM_CHAT_ID=222\nTIMEZONE=Europe/London\nQUIET_FROM=22:00\nQUIET_TO=07:00\n' > "${ROOT}/clients/acme/alerts.conf"
  printf 'Lead capture|2|40\nInvoice reminder|0|12\n' > "${STUB}/runs"
  cat > "${STUB}/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  ps) echo pgcid ;;
  exec) cat >/dev/null; cat "$(dirname "$0")/runs" ;;
esac
SH
  chmod +x "${STUB}/docker"
  export PATH="${STUB}:${PATH}"
  NOW="$(TZ=Europe/London date -d '2026-01-15 08:10' +%s)"
  add_backup 20260115T023000Z ok
}

teardown() {
  stop_mock_http
  rm -rf "$ROOT" "$STUB"
}

add_backup() {
  mkdir -p "${ROOT}/backups/acme/$1"
  printf '{"backup":"%s","local":"ok","remote":"%s"}\n' "$1" "$2" > "${ROOT}/backups/acme/$1/status.json"
  printf '%s\n' "$1" > "${ROOT}/backups/acme/latest"
}

digest_at() {
  OPSKIT_NOW="$1" run "$DIGEST" acme --root "$ROOT" "${@:2}"
}

owner_text() {
  mock_requests | jq -r .body | jq -r 'select(.chat_id == "111") | .text'
}

@test "sends one summary per day at the digest hour in the client's time zone" {
  digest_at "$(TZ=Europe/London date -d '2026-01-15 07:50' +%s)"
  [ "$(mock_requests | jq -s length)" = "0" ]
  digest_at "$NOW"
  [ "$status" -eq 0 ]
  digest_at "$((NOW + 1200))"
  [ "$(mock_requests | jq -r .body | jq -r .chat_id | sort | tr '\n' ' ')" = "111 222 " ]
  [ "$(cat "${ROOT}/state/acme/digest.last")" = "2026-01-15" ]
}

@test "summary lists backup, runs by failing flow and health; failures are named in the headline" {
  touch "${ROOT}/state/acme/health/disk.active"
  digest_at "$NOW"
  local text
  text="$(owner_text)"
  [[ "$text" == "[INFO] acme on "*": Daily summary for 2026-01-15: check failed runs, health — First action: Look at failed runs, health below"* ]]
  [[ "$text" == *"Backup: last 20260115T023000Z (5h ago), off-server: ok"* ]]
  [[ "$text" == *"Runs (24 h): 52, failed: 2"* ]]
  [[ "$text" == *"  - Lead capture: 2 of 40 failed"* ]]
  [[ "$text" != *"Invoice reminder:"* ]]
  [[ "$text" == *"Health: open problems: disk"* ]]
}

@test "an old or local-only backup is flagged" {
  add_backup 20260113T023000Z failed
  printf 'Lead capture|0|40\n' > "${STUB}/runs"
  digest_at "$NOW"
  [[ "$(owner_text)" == *": Daily summary for 2026-01-15: check backup —"* ]]
  [[ "$(owner_text)" == *"(53h ago), off-server: failed"* ]]
}

@test "all good when nothing is wrong" {
  printf 'Lead capture|0|40\n' > "${STUB}/runs"
  digest_at "$NOW"
  [[ "$(owner_text)" == *"Daily summary for 2026-01-15: all good — First action: Nothing to do"* ]]
}

@test "alerts held in quiet hours are delivered in the digest and then cleared" {
  local night
  night="$(TZ=Europe/London date -d '2026-01-15 01:00' +%s)"
  OPSKIT_NOW="$night" "${ROOT}/agent/alert.sh" --root "$ROOT" --client acme --severity warn --what "Disk 88% full on /" --action "free space" >/dev/null
  [ "$(wc -l < "${ROOT}/state/acme/held.jsonl")" -eq 1 ]
  digest_at "$NOW"
  local client_text
  client_text="$(mock_requests | jq -r .body | jq -r 'select(.chat_id == "222") | .text')"
  [[ "$client_text" == *"Held during quiet hours: 1"* ]]
  [[ "$client_text" == *"  - [warn] Disk 88% full on /"* ]]
  [ ! -e "${ROOT}/state/acme/held.jsonl" ]
}

@test "held alerts are kept when the digest cannot be delivered" {
  printf '{"severity":"warn","what":"x"}\n' > "${ROOT}/state/acme/held.jsonl"
  OPSKIT_TELEGRAM_API="http://127.0.0.1:9" digest_at "$NOW"
  [ "$(wc -l < "${ROOT}/state/acme/held.jsonl")" -eq 1 ]
}

@test "--now sends outside the digest hour and the summary ignores quiet hours" {
  digest_at "$(TZ=Europe/London date -d '2026-01-15 23:30' +%s)" --now
  [ "$(mock_requests | jq -r .body | jq -r .chat_id | sort | tr '\n' ' ')" = "111 222 " ]
}

@test "no backup at all is reported" {
  rm -rf "${ROOT}/backups"
  digest_at "$NOW"
  [[ "$(owner_text)" == *"Backup: NONE found"* ]]
}
