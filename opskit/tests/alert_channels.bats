#!/usr/bin/env bats

load helpers/common
load helpers/mock_http
load helpers/mock_smtp

setup() {
  ROOT="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme"
  cp "${OPSKIT_ROOT}/agent/alert.sh" "${ROOT}/agent/"
  cp -r "${OPSKIT_ROOT}/templates/alerts" "${ROOT}/agent/alerts"
  ALERT="${ROOT}/agent/alert.sh"
  start_mock_http
  start_mock_smtp
  export OPSKIT_TELEGRAM_API="$MOCK_URL"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${ROOT}/agent/alerts.conf"
}

teardown() {
  stop_mock_http
  stop_mock_smtp
  rm -rf "$ROOT"
}

send() {
  run "$ALERT" --root "$ROOT" --client acme --severity critical --what "3 runs of Lead capture failed" \
    --action "open the run and fix the step" --link "https://auto.acme.com/projects/p1/runs/r1" "$@"
}

smtp_owner() {
  printf 'SMTP_URL=%s\nSMTP_FROM=alerts@ops.example\nSMTP_TLS=none\n' "$SMTP_URL" >> "${ROOT}/agent/alerts.conf"
}

@test "telegram payload follows the template and carries the run link" {
  send
  [ "$status" -eq 0 ]
  local body
  body="$(mock_requests | jq -r .body)"
  [ "$(mock_requests | jq -r .path)" = "/bot123:abc/sendMessage" ]
  [ "$(jq -r .chat_id <<< "$body")" = "111" ]
  [ "$(jq -r .disable_web_page_preview <<< "$body")" = "true" ]
  [ "$(jq -r .text <<< "$body")" = "[CRITICAL] acme on $(hostname): 3 runs of Lead capture failed — First action: open the run and fix the step
https://auto.acme.com/projects/p1/runs/r1" ]
}

@test "slack payload is the same text" {
  printf 'SLACK_WEBHOOK_URL=%s/slack/T/B/C\n' "$MOCK_URL" > "${ROOT}/clients/acme/alerts.conf"
  send
  [ "$status" -eq 0 ]
  local body
  body="$(mock_requests | jq -c 'select(.path == "/slack/T/B/C") | .body | fromjson')"
  [ "$(jq -r 'keys | join(",")' <<< "$body")" = "text" ]
  [[ "$(jq -r .text <<< "$body")" == "[CRITICAL] acme on "*"— First action: open the run and fix the step"* ]]
}

@test "--owner-only reaches the owner and none of the client's channels" {
  printf 'TELEGRAM_CHAT_ID=222\nSLACK_WEBHOOK_URL=%s/slack/T/B/C\n' "$MOCK_URL" > "${ROOT}/clients/acme/alerts.conf"
  send --owner-only
  [ "$status" -eq 0 ]
  [ "$(mock_requests | jq -s length)" = "1" ]
  [ "$(mock_requests | jq -r '.body | fromjson | .chat_id')" = "111" ]
}

@test "email goes to every client recipient with subject and body from the template" {
  smtp_owner
  printf 'EMAIL_TO=ops@acme.example,boss@acme.example\n' > "${ROOT}/clients/acme/alerts.conf"
  send
  [ "$status" -eq 0 ]
  [ "$(mock_mails | jq -s length)" = "1" ]
  [ "$(mock_mails | jq -r '.rcpt | join(" ")')" = "<ops@acme.example> <boss@acme.example>" ]
  [ "$(mock_mails | jq -r .from)" = "<alerts@ops.example>" ]
  local data
  data="$(mock_mails | jq -r .data)"
  grep -q $'^Subject: \\[CRITICAL\\] acme: 3 runs of Lead capture failed\r$' <<< "$data"
  grep -q $'^To: ops@acme.example,boss@acme.example\r$' <<< "$data"
  grep -q 'https://auto.acme.com/projects/p1/runs/r1' <<< "$data"
}

@test "email authenticates with the owner's SMTP credentials (quotes and backslashes survive)" {
  smtp_owner
  printf 'SMTP_USER=mailer\nSMTP_PASSWORD=pa"ss\\word\n' >> "${ROOT}/agent/alerts.conf"
  printf 'EMAIL_TO=ops@acme.example\n' > "${ROOT}/clients/acme/alerts.conf"
  send
  [ "$status" -eq 0 ]
  [ "$(mock_mails | jq -r .auth)" = 'mailer:pa"ss\word' ]
}

@test "a newline in the text cannot add email headers" {
  smtp_owner
  printf 'EMAIL_TO=ops@acme.example\n' > "${ROOT}/clients/acme/alerts.conf"
  run "$ALERT" --root "$ROOT" --client acme --severity warn --what $'disk full\nBcc: evil@example.com' --action check
  [ "$status" -eq 0 ]
  ! mock_mails | jq -r .data | sed '/^\r$/q' | grep -q '^Bcc:'
}

@test "email without owner SMTP settings is reported, other channels still deliver" {
  printf 'EMAIL_TO=ops@acme.example\n' > "${ROOT}/clients/acme/alerts.conf"
  send
  [ "$status" -eq 1 ]
  [[ "$output" == *"email alert for ops@acme.example skipped"* ]]
  [ "$(mock_requests | jq -s length)" = "1" ]
}

@test "a failing channel does not stop the others and the exit code says so" {
  printf 'SLACK_WEBHOOK_URL=http://127.0.0.1:9/down\nWEBHOOK_URL=%s/client-hook\n' "$MOCK_URL" > "${ROOT}/clients/acme/alerts.conf"
  send
  [ "$status" -eq 1 ]
  [[ "$output" == *"slack alert failed"* ]]
  [ "$(mock_requests | jq -r .path | sort | tr '\n' ' ')" = "/bot123:abc/sendMessage /client-hook " ]
}

@test "webhook payload has the documented fields" {
  printf 'WEBHOOK_URL=%s/hook\n' "$MOCK_URL" > "${ROOT}/clients/acme/alerts.conf"
  send
  local body
  body="$(mock_requests | jq -c 'select(.path == "/hook") | .body | fromjson')"
  [ "$(jq -r 'keys | sort | join(",")' <<< "$body")" = "at,client,first_action,host,link,severity,what" ]
}

@test "link must be an http(s) URL" {
  run "$ALERT" --root "$ROOT" --client acme --severity info --what x --action y --link 'javascript:alert(1)'
  [ "$status" -eq 1 ]
  [ "$(mock_requests | jq -s length)" = "0" ]
}

@test "missing templates fail loudly" {
  rm -rf "${ROOT}/agent/alerts"
  OPSKIT_ALERT_TEMPLATES="" run env -u OPSKIT_ALERT_TEMPLATES bash -c "cp '$ALERT' '${ROOT}/alert-copy.sh' && '${ROOT}/alert-copy.sh' --root '$ROOT' --client acme --severity info --what x --action y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alert templates not found"* ]]
}
