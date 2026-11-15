#!/usr/bin/env bash
# Sending care reports (task 7.9): one multipart email (text + HTML) per client and month to client.yaml
# report.recipients with a copy to the owner, through the owner's SMTP account in <registry>/owner/alerts.conf
# (SMTP_URL, SMTP_FROM, SMTP_USER, SMTP_PASSWORD, SMTP_TLS, OWNER_EMAIL — the same keys alert.sh uses). The
# password goes to curl on stdin, never on the command line. clients/<id>/reports/sent.jsonl makes every month
# go out once. Needs report.sh, business.sh.

report_owner_conf() {
  local file
  file="$(registry_root)/owner/alerts.conf"
  [ -f "$file" ] || return 0
  sed -n "s/^${1}=//p" "$file" | tail -n 1
}

# report_curl_quote <value>: double-quoted for a curl config line (backslashes, then quotes escaped)
report_curl_quote() {
  local value="${1//\\/\\\\}"
  printf '"%s"' "${value//\"/\\\"}"
}

report_sent_before() {
  local file
  file="$(client_dir "$1")/reports/sent.jsonl"
  [ -f "$file" ] && jq -e --arg m "$2" 'select(.month == $m)' "$file" >/dev/null 2>&1
}

# report_b64_subject <text>: RFC 2047 encoded header value
report_b64_subject() {
  printf '=?UTF-8?B?%s?=' "$(printf '%s' "$1" | base64 -w0)"
}

# report_message <id> <month> <from> <to csv> <cc>: the MIME message on stdout
report_message() {
  local id="$1" month="$2" from="$3" to="$4" cc="$5" dir boundary label name
  dir="$(client_dir "$id")/reports"
  boundary="opskit-$(openssl rand -hex 12)"
  label="$(jq -r '.label' "${dir}/${month}.json")"
  name="$(jq -r '.client.name' "${dir}/${month}.json")"
  printf 'From: %s <%s>\r\n' "$(report_b64_subject "$(business_get business_name)")" "$from"
  printf 'To: %s\r\n' "$to"
  [ -z "$cc" ] || printf 'Cc: %s\r\n' "$cc"
  printf 'Subject: %s\r\n' "$(report_b64_subject "Care report ${label} — ${name}")"
  printf 'Date: %s\r\n' "$(date -R)"
  printf 'Message-ID: <%s@opskit>\r\n' "$(openssl rand -hex 16)"
  printf 'MIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary="%s"\r\n\r\n' "$boundary"
  printf -- '--%s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n' "$boundary"
  base64 -w 76 "${dir}/${month}.txt" | sed 's/$/\r/'
  printf -- '--%s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n' "$boundary"
  base64 -w 76 "${dir}/${month}.html" | sed 's/$/\r/'
  printf -- '--%s--\r\n' "$boundary"
}

# report_send <id> <month> [resend]: the report files must exist (report_build)
report_send() {
  local id="$1" month="$2" resend="${3:-false}" url from user password tls owner recipients to cc message args=() rcpt
  local dir
  dir="$(client_dir "$id")/reports"
  [ -f "${dir}/${month}.json" ] || { log_fail "no report of ${id} for ${month} yet: opskit report ${id} --month ${month}"; return 1; }
  if [ "$resend" != "true" ] && report_sent_before "$id" "$month"; then
    log_ok "report of ${id} for ${month} was already sent ($(jq -r --arg m "$month" 'select(.month == $m) | .at' "${dir}/sent.jsonl" | tail -n 1)); --resend to send again"
    return 0
  fi
  url="$(report_owner_conf SMTP_URL)"
  from="$(report_owner_conf SMTP_FROM)"
  if [ -z "$url" ] || [ -z "$from" ]; then
    log_fail "no SMTP_URL / SMTP_FROM in $(registry_root)/owner/alerts.conf: reports cannot be emailed"
    return 1
  fi
  user="$(report_owner_conf SMTP_USER)"
  password="$(report_owner_conf SMTP_PASSWORD)"
  tls="$(report_owner_conf SMTP_TLS)"
  owner="$(report_owner_conf OWNER_EMAIL)"
  [ -n "$owner" ] || owner="$(business_get support_email)"
  recipients="$(yq -r '.report.recipients // [] | .[]' "$(client_file "$id")")"
  [ -n "$recipients" ] || { log_fail "${id} has no report.recipients in client.yaml"; return 1; }
  to="$(paste -sd, <<< "$recipients" | sed 's/,/, /g')"
  cc="$owner"
  message="$(mktemp)"
  report_message "$id" "$month" "$from" "$to" "$cc" > "$message"
  args=(-sS -m 60 --url "$url" --mail-from "$from" --upload-file "$message")
  [ "${tls:-starttls}" = "none" ] || args+=(--ssl-reqd)
  while IFS= read -r rcpt; do
    [ -n "$rcpt" ] && args+=(--mail-rcpt "$rcpt")
  done <<< "${recipients}"$'\n'"${cc}"
  if [ -n "$user" ]; then
    curl "${args[@]}" -K - <<< "user = $(report_curl_quote "${user}:${password}")" >/dev/null || { rm -f "$message"; log_fail "sending the report of ${id} failed (SMTP)"; return 1; }
  else
    curl "${args[@]}" >/dev/null || { rm -f "$message"; log_fail "sending the report of ${id} failed (SMTP)"; return 1; }
  fi
  rm -f "$message"
  jq -nc --arg month "$month" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg to "$to" --arg cc "$cc" \
    '{month: $month, at: $at, to: $to, cc: $cc}' >> "${dir}/sent.jsonl"
  log_ok "report of ${id} for ${month} emailed to ${to} (copy to ${cc})"
}

# report_all <month|""> <send true|false> <resend>: every deployed client; one failure does not stop the others
report_all() {
  local month="$1" send="$2" resend="$3" file id failed=0 m
  for file in "$(registry_root)"/clients/*/client.yaml; do
    [ -f "$file" ] || continue
    [ "$(yaml_get "$file" .status)" = "deployed" ] || continue
    id="$(yaml_get "$file" .client_id)"
    m="${month:-$(report_last_month "$(yaml_get "$file" .timezone UTC)")}"
    if [ "$send" = "true" ] && [ "$resend" != "true" ] && report_sent_before "$id" "$m"; then
      log_ok "report of ${id} for ${m} was already sent"
      continue
    fi
    report_build "$id" "$m" || { failed=1; continue; }
    [ "$send" != "true" ] || report_send "$id" "$m" "$resend" || failed=1
  done
  return "$failed"
}
