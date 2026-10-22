#!/usr/bin/env bats

load helpers/common
load helpers/registry
load helpers/mock_smtp

setup() {
  make_registry
  new_demo_client acme acme.example.com
  yq -i '.status = "deployed" | .name = "Acme Dental" | .report.recipients = ["anna@acme-dental.example", "office@acme-dental.example"]' "${REG}/clients/acme/client.yaml"
  start_mock_smtp
  mkdir -p "${REG}/owner" "${REG}/clients/acme/reports"
  printf 'SMTP_URL=%s\nSMTP_FROM=reports@brightops.example\nSMTP_TLS=none\nSMTP_USER=reports@brightops.example\nSMTP_PASSWORD=pa"ss\\word\nOWNER_EMAIL=me@brightops.example\n' "$SMTP_URL" > "${REG}/owner/alerts.conf"
  for lib in log validate schema registry ssh host business report report_send; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  local fixture="${BATS_TEST_DIRNAME}/fixtures/report"
  cp "${fixture}/2026-09.json" "${fixture}/2026-09.txt" "${REG}/clients/acme/reports/"
  report_render "$(cat "${fixture}/2026-09.json")" html > "${REG}/clients/acme/reports/2026-09.html"
}

teardown() {
  stop_mock_smtp
  rm -rf "$REG"
}

decode_part() {
  mock_mails | jq -r '.data' | tr -d '\r' | awk -v t="$1" '
    $0 ~ "^Content-Type: " t { head = 1; next }
    head && $0 == "" { head = 0; grab = 1; next }
    grab && /^--opskit-/ { exit }
    grab && NF { print }' | base64 -d
}

@test "the report goes to the client's recipients with a copy to the owner, text and HTML parts intact" {
  run report_send acme 2026-09
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] report of acme for 2026-09 emailed to anna@acme-dental.example, office@acme-dental.example (copy to me@brightops.example)"* ]]
  [ "$(mock_mails | jq -s length)" = "1" ]
  [ "$(mock_mails | jq -c '.rcpt')" = '["<anna@acme-dental.example>","<office@acme-dental.example>","<me@brightops.example>"]' ]
  [ "$(mock_mails | jq -r '.auth')" = 'reports@brightops.example:pa"ss\word' ]
  local data subject
  data="$(mock_mails | jq -r '.data' | tr -d '\r')"
  [[ "$data" == *"Content-Type: multipart/alternative"* ]]
  [[ "$data" == *"Cc: me@brightops.example"* ]]
  subject="$(sed -n 's/^Subject: =?UTF-8?B?\(.*\)?=$/\1/p' <<< "$data" | base64 -d)"
  [ "$subject" = "Care report September 2026 — Acme Dental" ]
  diff <(decode_part text/plain) "${REG}/clients/acme/reports/2026-09.txt"
  [[ "$(decode_part text/html)" == *"Care report — September 2026"* ]]
}

@test "a month is sent once; --resend sends it again" {
  report_send acme 2026-09 >/dev/null
  run report_send acme 2026-09
  [ "$status" -eq 0 ]
  [[ "$output" == *"was already sent"*"--resend to send again"* ]]
  [ "$(mock_mails | jq -s length)" = "1" ]
  run report_send acme 2026-09 true
  [ "$status" -eq 0 ]
  [ "$(mock_mails | jq -s length)" = "2" ]
  [ "$(jq -s length "${REG}/clients/acme/reports/sent.jsonl")" = "2" ]
}

@test "no SMTP settings, no recipients or no report file stop with a clear message and send nothing" {
  run report_send acme 2026-08
  [ "$status" -eq 1 ]
  [[ "$output" == *"no report of acme for 2026-08 yet"* ]]
  yq -i '.report.recipients = []' "${REG}/clients/acme/client.yaml"
  run report_send acme 2026-09
  [ "$status" -eq 1 ]
  [[ "$output" == *"acme has no report.recipients"* ]]
  rm "${REG}/owner/alerts.conf"
  run report_send acme 2026-09
  [ "$status" -eq 1 ]
  [[ "$output" == *"no SMTP_URL / SMTP_FROM"* ]]
  [ "$(mock_mails | jq -s length)" = "0" ]
  [ ! -f "${REG}/clients/acme/reports/sent.jsonl" ]
}

@test "--all builds and sends every deployed client, skips months already sent, keeps going after a failure" {
  new_demo_client beta beta.example.com
  yq -i '.status = "draft"' "${REG}/clients/beta/client.yaml"
  report_build() { [ "$1" = "acme" ] || return 1; log_ok "built $1 $2"; }
  run report_all 2026-09 true false
  [ "$status" -eq 0 ]
  [[ "$output" == *"built acme 2026-09"* ]]
  [[ "$output" != *"beta"* ]]
  [ "$(mock_mails | jq -s length)" = "1" ]
  run report_all 2026-09 true false
  [[ "$output" == *"report of acme for 2026-09 was already sent"* ]]
  [ "$(mock_mails | jq -s length)" = "1" ]
}

@test "opskit report: --resend needs --send, --all takes no client id" {
  run "$OPSKIT" report acme --resend
  [ "$status" -eq 1 ]
  run "$OPSKIT" report acme --all
  [ "$status" -eq 1 ]
  run "$OPSKIT" report --all --month 2026-9
  [ "$status" -eq 1 ]
}
