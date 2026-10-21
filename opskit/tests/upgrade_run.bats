#!/usr/bin/env bats

load helpers/common
load helpers/mock_http
load helpers/registry
load helpers/upgrade

setup() {
  upgrade_setup
  STUB="$(mktemp -d)"
  export FAKE_DOCKER_LOG="${STUB}/docker.log" FAKE_INSPECTS="${STUB}/inspects"
  cat > "${STUB}/docker" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "pull -q") echo "pull $3" >> "$FAKE_DOCKER_LOG"; exit "${FAKE_PULL_RC:-0}" ;;
  "image inspect")
    [ "$3" = "--format" ] && echo x >> "$FAKE_INSPECTS"
    digest="sha256:aaa"
    [ -n "${FAKE_HOST_DIGEST:-}" ] && [ "$(wc -l < "$FAKE_INSPECTS")" = "2" ] && digest="$FAKE_HOST_DIGEST"
    image="${*: -1}"
    printf 'other/repo@sha256:zzz\n%s@%s\n' "${image%:*}" "$digest"
    ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${STUB}/docker"
  export PATH="${STUB}:${PATH}"
  LOCK="${HOSTROOT}/state/acme/upgrade.lock"
}

teardown() {
  upgrade_teardown
  rm -rf "$STUB"
}

# go <args>: runs opskit upgrade acme <args> with "acme" typed at the confirmation prompt
go() {
  run bash -c 'printf "acme\n" | "$0" upgrade acme "$@"' "$OPSKIT" "$@"
}

state() {
  cat "${REG}"/clients/acme/upgrades/*/state.json
}

# fake_run <run id> <steps json>: an upgrade that was killed while running, holding the lock
fake_run() {
  mkdir -p "${REG}/clients/acme/upgrades/$1" "$LOCK"
  jq -n --arg run "$1" --argjson steps "$2" '{client: "acme", run: $run, repo: "ghcr.io/activepieces/activepieces",
    from: "0.91.4", to: "0.92.3", started: "2026-10-22T10:00:00Z", status: "running", steps: $steps}' \
    > "${REG}/clients/acme/upgrades/$1/state.json"
  echo "$1" > "${LOCK}/run"
}

@test "an upgrade pulls the image here and on the host, records the digest and releases the lock when a later step stops it" {
  go --to 0.92.3 --yes --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"[ok] no other upgrade of acme is running"* ]]
  [[ "$output" == *"[ok] ghcr.io/activepieces/activepieces:0.92.3 pulled here and on local-practice (sha256:aaa)"* ]]
  [[ "$output" == *"staging: could not read acme's counts"* ]]
  [[ "$output" == *"stopped at stage; nothing changed on the client"* ]]
  [ "$(grep -c 'pull ghcr.io/activepieces/activepieces:0.92.3' "$FAKE_DOCKER_LOG")" = "2" ]
  [ "$(state | jq -r '.status, .failed_step, .digest, .steps.pull.status, .steps.stage.status' | paste -sd' ')" = "failed stage sha256:aaa done failed" ]
  [ "$(state | jq -r '.from, .to')" = $'0.91.4\n0.92.3' ]
  [ ! -e "$LOCK" ]
}

@test "a different digest on the host or a failed pull stops the upgrade before the client is touched" {
  FAKE_HOST_DIGEST=sha256:bbb go --to 0.92.3 --yes --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs between here (sha256:aaa) and local-practice (sha256:bbb)"* ]]
  [ "$(state | jq -r '.failed_step')" = "pull" ]
  [ ! -e "$LOCK" ]
  rm -rf "${REG}/clients/acme/upgrades"
  FAKE_PULL_RC=1 go --to 0.92.3 --yes --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not pull ghcr.io/activepieces/activepieces:0.92.3 here"* ]]
  [ ! -e "$LOCK" ]
}

@test "a second upgrade is refused while another one holds the lock" {
  mkdir -p "$LOCK"
  echo "$(date -u +%Y%m%dT%H%M%SZ)" > "${LOCK}/run"
  run "$OPSKIT" upgrade acme --to 0.92.3 --plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"from another machine) holds the lock of acme: if no upgrade is running, opskit upgrade acme --unlock"* ]]
  [[ "$output" != *"looks stale"* ]]
  go --to 0.92.3 --yes --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"a gate failed: nothing was changed"* ]]
  [ ! -f "$FAKE_DOCKER_LOG" ]
  [ -d "$LOCK" ]
  echo 20200101T000000Z > "${LOCK}/run"
  run "$OPSKIT" upgrade acme --to 0.92.3 --plan
  [[ "$output" == *"looks stale"* ]]
}

@test "a killed upgrade before the switch names --resume, which continues at the step it stopped" {
  fake_run 20261022T100000Z '{"pull": {"status": "done"}, "stage": {"status": "running"}}'
  run "$OPSKIT" upgrade acme --to 0.92.3 --plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"upgrade 20261022T100000Z of acme to 0.92.3 was interrupted at step stage: nothing changed on the client yet: opskit upgrade acme --resume"* ]]
  go --resume --yes --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"Resuming upgrade 20261022T100000Z of acme to 0.92.3 at step stage"* ]]
  [[ "$output" == *"staging: could not read acme's counts"* ]]
  [ ! -f "$FAKE_DOCKER_LOG" ]
  [ "$(state | jq -r '.status')" = "failed" ]
  [ ! -e "$LOCK" ]
  go --resume --yes --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"no unfinished upgrade of acme to resume"* ]]
}

@test "a killed upgrade after the switch started only allows a rollback" {
  fake_run 20261022T100000Z '{"pull": {"status": "done"}, "stage": {"status": "done"}, "switch": {"status": "running"}}'
  run "$OPSKIT" upgrade acme --to 0.92.3 --plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"interrupted at step switch: the client may already run the new version: opskit upgrade acme --rollback"* ]]
  go --resume --yes --now
  [ "$status" -eq 1 ]
  [[ "$output" == *"reached the switch: opskit upgrade acme --rollback"* ]]
  run "$OPSKIT" upgrade acme --unlock
  [ "$status" -eq 1 ]
  [[ "$output" == *"--rollback instead"* ]]
  [ -d "$LOCK" ]
  [ "$(state | jq -r '.status')" = "running" ]
}

@test "--unlock gives up an interrupted upgrade that never reached the switch" {
  fake_run 20261022T100000Z '{"pull": {"status": "running"}}'
  run "$OPSKIT" upgrade acme --unlock
  [ "$status" -eq 0 ]
  [[ "$output" == *"upgrade lock of acme released (run 20261022T100000Z)"* ]]
  [ ! -e "$LOCK" ]
  [ "$(state | jq -r '.status')" = "abandoned" ]
  run "$OPSKIT" upgrade acme --unlock
  [ "$status" -eq 0 ]
  [[ "$output" == *"no upgrade lock on acme"* ]]
}

@test "the leftover lock of a finished upgrade is cleared by the next plan" {
  fake_run 20261022T100000Z '{}'
  jq '.status = "done"' "${REG}/clients/acme/upgrades/20261022T100000Z/state.json" > "${STUB}/s" \
    && mv "${STUB}/s" "${REG}/clients/acme/upgrades/20261022T100000Z/state.json"
  run "$OPSKIT" upgrade acme --to 0.92.3 --plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] removed the leftover lock of finished upgrade 20261022T100000Z (done)"* ]]
  [ ! -e "$LOCK" ]
}

@test "an upgrade waits for a running backup and gives up without changes" {
  mkdir -p "${HOSTROOT}/backups/acme"
  local holder
  flock "${HOSTROOT}/backups/acme/.lock" sleep 5 3>&- &
  holder=$!
  sleep 0.5
  OPSKIT_UPGRADE_BACKUP_WAIT_S=1 go --to 0.92.3 --yes --now
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [[ "$output" == *"a backup of acme is still running after 1 s: try again later"* ]]
  [ ! -e "$LOCK" ]
  [ ! -d "${REG}/clients/acme/upgrades" ]
  [ ! -f "$FAKE_DOCKER_LOG" ]
}

@test "the upgrade needs --yes, the typed client id and the client's quiet hours (or --now)" {
  run "$OPSKIT" upgrade acme --to 0.92.3 --now < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"is destructive: re-run with --yes"* ]]
  run bash -c 'printf "other\n" | "$0" upgrade acme --to 0.92.3 --yes --now' "$OPSKIT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"typed id does not match acme; nothing was changed"* ]]
  go --to 0.92.3 --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"acme has no quiet hours (alerts.quiet_hours): agree a time with the client and add --now"* ]]
  yq -i '.timezone = "Europe/Berlin" | .alerts.quiet_hours = {"from": "22:00", "to": "06:00"}' "${REG}/clients/acme/client.yaml"
  OPSKIT_UPGRADE_CLOCK="$(date -d '2026-10-22T12:00:00Z' +%s)" go --to 0.92.3 --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside acme's quiet hours (22:00–06:00 Europe/Berlin): run then, or add --now"* ]]
  [ ! -f "$FAKE_DOCKER_LOG" ]
  [ ! -e "$LOCK" ]
  OPSKIT_UPGRADE_CLOCK="$(date -d '2026-10-22T23:30:00Z' +%s)" go --to 0.92.3 --yes
  [[ "$output" == *"[ok] confirmed: upgrade acme to 0.92.3"* ]]
  [ -f "$FAKE_DOCKER_LOG" ]
}
