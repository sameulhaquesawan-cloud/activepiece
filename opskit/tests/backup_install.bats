#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  HOSTROOT="$(mktemp -d)"
  yq -i ".opskit_root = \"${HOSTROOT}\"" "${REG}/hosts/local-practice.yaml"
  STUB="$(mktemp -d)"
  CRONTAB_DATA="${STUB}/crontab.data"
  printf '#!/usr/bin/env bash\nif [ "$1" = "-l" ]; then cat "%s" 2>/dev/null || exit 1; else cp "$1" "%s"; fi\n' "$CRONTAB_DATA" "$CRONTAB_DATA" > "${STUB}/crontab"
  chmod +x "${STUB}/crontab"
  export PATH="${STUB}:${PATH}"
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
  source "${OPSKIT_ROOT}/lib/schema.sh"
  source "${OPSKIT_ROOT}/lib/registry.sh"
  source "${OPSKIT_ROOT}/lib/render.sh"
  source "${OPSKIT_ROOT}/lib/secrets.sh"
  source "${OPSKIT_ROOT}/lib/stack.sh"
  source "${OPSKIT_ROOT}/lib/ssh.sh"
  source "${OPSKIT_ROOT}/lib/host.sh"
  source "${OPSKIT_ROOT}/lib/deploy.sh"
  KEYDIR="$(mktemp -d)"
  age-keygen -o "${KEYDIR}/key" 2>/dev/null
  age-keygen -y "${KEYDIR}/key" > "${KEYDIR}/owner.age.pub"
}

teardown() {
  rm -rf "$REG" "$HOSTROOT" "$STUB" "$KEYDIR"
}

@test "render writes backup.conf and client alerts.conf from client.yaml (600)" {
  yq -i '.backup.remote = "b2-acme:acme-backups" | .backup.retention_days.local = 7 | .backup.heartbeat_url = "https://status.example.com/api/push/xyz" | .alerts.channels = ["telegram","slack"] | .alerts.telegram.chat_id = "-100123" | .alerts.slack.webhook_secret = "SLACK_HOOK"' "${REG}/clients/demo/client.yaml"
  printf 'SLACK_HOOK=https://hooks.slack.com/services/T/B/C\n' > "${REG}/clients/demo/channels.env"
  run "$OPSKIT" render demo
  [ "$status" -eq 0 ]
  local out="${REG}/clients/demo/rendered"
  grep -qx 'BACKUP_REMOTE=b2-acme:acme-backups' "${out}/backup.conf"
  grep -qx 'KEEP_LOCAL_DAYS=7' "${out}/backup.conf"
  grep -qx 'KEEP_REMOTE_DAYS=30' "${out}/backup.conf"
  grep -qx 'HEARTBEAT_URL=https://status.example.com/api/push/xyz' "${out}/backup.conf"
  grep -qx 'TELEGRAM_CHAT_ID=-100123' "${out}/alerts.conf"
  grep -qx 'SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T/B/C' "${out}/alerts.conf"
  [ "$(stat -c %a "${out}/backup.conf")" = "600" ]
  [ "$(stat -c %a "${out}/alerts.conf")" = "600" ]
  grep -q "# opskit:demo$" "${out}/cron"
}

@test "without the owner key, deploy installs no backup agent and says why" {
  "$OPSKIT" render demo >/dev/null
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/missing.pub" run deploy_install_agents local-practice demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"backups NOT installed for demo"* ]]
  [ ! -e "${HOSTROOT}/agent/backup.sh" ]
  [ ! -e "${HOSTROOT}/clients/demo/backup.conf" ]
}

@test "without the owner key, monitoring is still installed and scheduled (no backup line)" {
  "$OPSKIT" render demo >/dev/null
  yq -i '.install_cron = true' "${REG}/hosts/local-practice.yaml"
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/missing.pub" run deploy_install_agents local-practice demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"monitoring agents installed (failed runs every 5 min, health hourly, daily digest, watchdog every 2 min)"* ]]
  local script
  for script in alert.sh detect-failed-runs.sh health.sh digest.sh watchdog.sh; do
    [ "$(stat -c %a "${HOSTROOT}/agent/${script}")" = "755" ]
  done
  [ "$(grep -c '# opskit:demo$' "$CRONTAB_DATA")" = "4" ]
  ! grep -q 'agent/backup.sh' "$CRONTAB_DATA"
}

@test "a client that already has nightly backups is not re-deployed without the owner key (backup line kept)" {
  "$OPSKIT" render demo >/dev/null
  yq -i '.install_cron = true' "${REG}/hosts/local-practice.yaml"
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/owner.age.pub" run deploy_install_agents local-practice demo
  [ "$status" -eq 0 ]
  grep -q 'agent/backup.sh demo' "$CRONTAB_DATA"
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/missing.pub" run deploy_install_agents local-practice demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"demo already has nightly backups on local-practice: refusing to deploy without the owner public key"* ]]
  grep -q 'agent/backup.sh demo' "$CRONTAB_DATA"
  [ -s "${HOSTROOT}/clients/demo/backup.conf" ]
}

@test "rendered cron schedules backup nightly, detector every 5 min, health and digest hourly, watchdog every 2 min" {
  "$OPSKIT" render demo >/dev/null
  local cron="${REG}/clients/demo/rendered/cron" root
  root="$(yq -r .opskit_root "${REG}/hosts/local-practice.yaml")"
  [ "$(grep -c . "$cron")" = "5" ]
  grep -qx "\*/2 \* \* \* \* ${root}/agent/watchdog.sh demo --root ${root} >> ${root}/logs/demo-watchdog.log 2>&1 # opskit:demo" "$cron"
  grep -qx "30 2 \* \* \* ${root}/agent/backup.sh demo --root ${root} >> ${root}/logs/demo-backup.log 2>&1 # opskit:demo" "$cron"
  grep -qx "\*/5 \* \* \* \* ${root}/agent/detect-failed-runs.sh demo --root ${root} >> ${root}/logs/demo-detector.log 2>&1 # opskit:demo" "$cron"
  grep -qx "17 \* \* \* \* ${root}/agent/health.sh demo --root ${root} >> ${root}/logs/demo-health.log 2>&1 # opskit:demo" "$cron"
  grep -qx "2 \* \* \* \* ${root}/agent/digest.sh demo --root ${root} >> ${root}/logs/demo-digest.log 2>&1 # opskit:demo" "$cron"
}

@test "with the owner key, agent + configs land with the right modes; no cron on practice hosts" {
  "$OPSKIT" render demo >/dev/null
  mkdir -p "${REG}/owner"
  printf 'WEBHOOK_URL=http://127.0.0.1:9/hook\n' > "${REG}/owner/alerts.conf"
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/owner.age.pub" run deploy_install_agents local-practice demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"no cron on practice host"* ]]
  [ "$(stat -c %a "${HOSTROOT}/agent/backup.sh")" = "755" ]
  [ "$(stat -c %a "${HOSTROOT}/agent/alerts.conf")" = "600" ]
  [ "$(stat -c %a "${HOSTROOT}/clients/demo/backup.conf")" = "600" ]
  cmp -s "${KEYDIR}/owner.age.pub" "${HOSTROOT}/agent/owner.age.pub"
  [ ! -e "$CRONTAB_DATA" ]
  local template
  for template in text telegram slack email webhook; do
    cmp -s "${OPSKIT_ROOT}/templates/alerts/${template}.jq" "${HOSTROOT}/agent/alerts/${template}.jq"
  done
}

@test "render writes the client's email recipients when email is a channel" {
  yq -i '.alerts.channels = ["telegram","email"] | .alerts.telegram.chat_id = "-100123" | .alerts.email.to = ["ops@acme.example","boss@acme.example"]' "${REG}/clients/demo/client.yaml"
  run "$OPSKIT" render demo
  [ "$status" -eq 0 ]
  grep -qx 'EMAIL_TO=ops@acme.example,boss@acme.example' "${REG}/clients/demo/rendered/alerts.conf"
}

@test "render writes the client's time zone and quiet hours" {
  yq -i '.timezone = "Europe/London" | .alerts.quiet_hours = {"from": "22:00", "to": "07:00"}' "${REG}/clients/demo/client.yaml"
  run "$OPSKIT" render demo
  [ "$status" -eq 0 ]
  local conf="${REG}/clients/demo/rendered/alerts.conf"
  grep -qx 'TIMEZONE=Europe/London' "$conf"
  grep -qx 'APP_URL=https://demo.localhost:18443' "$conf"
  grep -qx 'TLS_MODE=internal' "$conf"
  grep -qx 'ERROR_EXCERPTS=true' "$conf"
  yq -i '.alerts.include_error_excerpt = false' "${REG}/clients/demo/client.yaml"
  "$OPSKIT" render demo >/dev/null
  grep -qx 'ERROR_EXCERPTS=false' "$conf"
  grep -qx 'QUIET_FROM=22:00' "$conf"
  grep -qx 'QUIET_TO=07:00' "$conf"
}

@test "cron sync keeps foreign lines, adds each client once, and drops removed clients" {
  printf '0 5 * * * /usr/local/bin/someone-elses-job\n' > "$CRONTAB_DATA"
  "$OPSKIT" render demo >/dev/null
  yq -i '.install_cron = true' "${REG}/hosts/local-practice.yaml"
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/owner.age.pub" run deploy_install_agents local-practice demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"monitoring + backup agents installed; nightly backup (30 2 * * *)"* ]]
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/owner.age.pub" deploy_install_agents local-practice demo >/dev/null
  grep -qx '0 5 \* \* \* /usr/local/bin/someone-elses-job' "$CRONTAB_DATA"
  [ "$(grep -c '# opskit:demo$' "$CRONTAB_DATA")" = "5" ]
  rm "${HOSTROOT}/clients/demo/cron"
  "${HOSTROOT}/agent/cron-sync.sh" --root "$HOSTROOT"
  [ "$(grep -c '# opskit:' "$CRONTAB_DATA")" = "0" ]
  grep -q someone-elses-job "$CRONTAB_DATA"
}
