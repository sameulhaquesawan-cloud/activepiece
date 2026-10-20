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
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/missing.pub" run deploy_install_backup local-practice demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"backups NOT installed for demo"* ]]
  [ ! -e "${HOSTROOT}/agent/backup.sh" ]
}

@test "with the owner key, agent + configs land with the right modes; no cron on practice hosts" {
  "$OPSKIT" render demo >/dev/null
  mkdir -p "${REG}/owner"
  printf 'WEBHOOK_URL=http://127.0.0.1:9/hook\n' > "${REG}/owner/alerts.conf"
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/owner.age.pub" run deploy_install_backup local-practice demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"no cron on practice host"* ]]
  [ "$(stat -c %a "${HOSTROOT}/agent/backup.sh")" = "755" ]
  [ "$(stat -c %a "${HOSTROOT}/agent/alerts.conf")" = "600" ]
  [ "$(stat -c %a "${HOSTROOT}/clients/demo/backup.conf")" = "600" ]
  cmp -s "${KEYDIR}/owner.age.pub" "${HOSTROOT}/agent/owner.age.pub"
  [ ! -e "$CRONTAB_DATA" ]
}

@test "cron sync keeps foreign lines, adds each client once, and drops removed clients" {
  printf '0 5 * * * /usr/local/bin/someone-elses-job\n' > "$CRONTAB_DATA"
  "$OPSKIT" render demo >/dev/null
  yq -i '.install_cron = true' "${REG}/hosts/local-practice.yaml"
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/owner.age.pub" run deploy_install_backup local-practice demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"nightly schedule installed (30 2 * * *)"* ]]
  OPSKIT_OWNER_AGE_PUB="${KEYDIR}/owner.age.pub" deploy_install_backup local-practice demo >/dev/null
  grep -qx '0 5 \* \* \* /usr/local/bin/someone-elses-job' "$CRONTAB_DATA"
  [ "$(grep -c '# opskit:demo$' "$CRONTAB_DATA")" = "1" ]
  rm "${HOSTROOT}/clients/demo/cron"
  "${HOSTROOT}/agent/cron-sync.sh" --root "$HOSTROOT"
  [ "$(grep -c '# opskit:' "$CRONTAB_DATA")" = "0" ]
  grep -q someone-elses-job "$CRONTAB_DATA"
}
