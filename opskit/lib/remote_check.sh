#!/usr/bin/env bash
# remote_check: read-only (optionally write) check of an rclone remote with the owner's rclone.conf.
# Prints classified reasons only, never rclone's own output (it can echo account ids or URLs with keys).

remote_check_conf() {
  printf '%s/owner/rclone.conf' "$(registry_root)"
}

remote_check_rclone() {
  rclone --config "$(remote_check_conf)" "$@"
}

# remote_check_reason <stderr file>: one plain sentence for a failed rclone call
remote_check_reason() {
  local err="$1"
  if grep -qi "didn't find section in config" "$err"; then
    printf 'the remote name is not in %s' "$(remote_check_conf)"
  elif grep -qiE 'Get "https?://[^"]*": |no such host|i/o timeout|timed out|connection refused|connection reset' "$err"; then
    printf 'the storage service could not be reached from this machine (network)'
  elif grep -qiE 'unauthorized|bad_auth_token|access denied|invalid.*(key|credentials)|(^|[^0-9])40[13]([^0-9]|$)' "$err"; then
    printf 'the key was refused (wrong key id / application key, or the key is not allowed on this bucket)'
  elif grep -qiE 'bucket.*not.*found|no such bucket|bucket_not_found' "$err"; then
    printf 'the bucket does not exist (check the name after the colon)'
  elif grep -qiE 'directory not found|not found|(^|[^0-9])404([^0-9]|$)' "$err"; then
    printf 'not found (check the bucket name after the colon)'
  else
    printf 'rclone could not use it'
  fi
}

# remote_check <remote:path> <write: true|false>: [ok]/[warn]/[fail] lines, non-zero on failure
remote_check() {
  local target="$1" write="$2" conf name rest bucket err rc=0 probe
  if ! [[ "$target" =~ ^[A-Za-z0-9_-]+:[A-Za-z0-9_./-]*$ ]]; then
    log_fail "remote: '${target}' is not <remote>:<bucket>[/path] (example: b2:my-backups/clients)"
    return 1
  fi
  conf="$(remote_check_conf)"
  if [ ! -f "$conf" ]; then
    log_fail "remote: no ${conf} (create it: rclone config --config ${conf}; docs/runbooks/backup-restore.md)"
    return 1
  fi
  [ "$(stat -c %a "$conf")" = "600" ] || log_warn "remote: ${conf} should be private (chmod 600 ${conf})"
  name="${target%%:*}"
  rest="${target#*:}"
  bucket="${rest%%/*}"
  err="$(mktemp)"
  if ! remote_check_rclone listremotes 2>/dev/null | grep -qx "${name}:"; then
    rm -f "$err"
    log_fail "remote: '${name}' is not defined in ${conf}"
    return 1
  fi
  if ! remote_check_rclone lsf --max-depth 1 "${name}:${bucket}" >/dev/null 2>"$err"; then
    log_fail "remote: ${name}:${bucket}: $(remote_check_reason "$err")"
    rm -f "$err"
    return 1
  fi
  log_ok "remote: ${name}:${bucket} answers with this key"
  if [ "$rest" != "$bucket" ] && ! remote_check_rclone lsf --max-depth 1 "$target" >/dev/null 2>"$err"; then
    if grep -qiE 'directory not found|not found' "$err"; then
      log_ok "remote: ${target} does not exist yet (the first backup creates it)"
    else
      log_fail "remote: ${target}: $(remote_check_reason "$err")"
      rm -f "$err"
      return 1
    fi
  fi
  if [ "$write" = "true" ]; then
    probe="${target%/}/opskit-write-test-$(date -u +%Y%m%dT%H%M%SZ)"
    if ! printf 'opskit write test\n' | remote_check_rclone rcat "$probe" 2>"$err"; then
      log_fail "remote: cannot write to ${target}: $(remote_check_reason "$err") (the key needs writeFiles)"
      rc=1
    elif ! remote_check_rclone deletefile "$probe" 2>"$err"; then
      log_warn "remote: wrote ${probe} but cannot delete it: old backups will never be pruned (the key needs deleteFiles)"
    else
      log_ok "remote: write and delete work (test file removed)"
    fi
  fi
  rm -f "$err"
  return "$rc"
}
