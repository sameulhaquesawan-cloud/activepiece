#!/usr/bin/env bash
# Backup of the operator's own registry (clients/, hosts/, owner/ — git-ignored, full of secrets): one tar
# archive encrypted to the owner's age public key, kept in a local folder outside the repo and optionally
# copied to an rclone remote (the owner's rclone.conf). Restore never overwrites without --overwrite --yes and
# moves the current folders aside instead of deleting them. Needs registry.sh, confirm.sh, deploy.sh
# (owner_age_pubkey), restore.sh (owner_age_identity).

REGISTRY_PARTS=(clients hosts owner)
REGISTRY_KEEP_LOCAL="${OPSKIT_REGISTRY_KEEP:-10}"
REGISTRY_KEEP_REMOTE=30

registry_backup_dir() {
  printf '%s' "${OPSKIT_REGISTRY_BACKUPS:-${HOME}/opskit-registry-backups}"
}

# registry_rclone <args…>: rclone with the owner's config when there is one
registry_rclone() {
  local conf
  conf="$(registry_root)/owner/rclone.conf"
  if [ -f "$conf" ]; then rclone --config "$conf" "$@"; else rclone "$@"; fi
}

# registry_backup [remote:path]: prints nothing secret; the archive name on success
registry_backup() {
  local remote="${1:-}" root dir name parts=() part tmp count
  root="$(registry_root)"
  [ -s "$(owner_age_pubkey)" ] || { log_fail "no owner age public key ($(owner_age_pubkey)): see docs/runbooks/backup-restore.md §A"; return 1; }
  for part in "${REGISTRY_PARTS[@]}"; do
    [ -d "${root}/${part}" ] && parts+=("$part")
  done
  [ "${#parts[@]}" -gt 0 ] || { log_fail "nothing to back up in ${root} (no clients/, hosts/ or owner/)"; return 1; }
  dir="$(registry_backup_dir)"
  (umask 077 && mkdir -p "$dir")
  chmod 700 "$dir"
  name="registry-$(date -u +%Y%m%dT%H%M%SZ).tar.gz.age"
  tmp="$(mktemp "${dir}/.partial.XXXXXX")"
  chmod 600 "$tmp"
  if ! tar -C "$root" -czf - "${parts[@]}" | age -R "$(owner_age_pubkey)" -o "$tmp"; then
    rm -f "$tmp"
    log_fail "registry archive could not be written or encrypted"
    return 1
  fi
  mv "$tmp" "${dir}/${name}"
  if [ -r "$(owner_age_identity)" ]; then
    count="$(age -d -i "$(owner_age_identity)" "${dir}/${name}" | tar -tzf - | grep -c . || true)"
    [ "${count:-0}" -gt 0 ] || { log_fail "the new archive does not decrypt with $(owner_age_identity)"; return 1; }
    log_ok "registry backup ${name}: ${parts[*]} (${count} entries, encrypted, checked with your private key)"
  else
    log_ok "registry backup ${name}: ${parts[*]} (encrypted; private key not on this machine, not test-decrypted)"
  fi
  log_info "  $(registry_backup_dir)/${name}"
  registry_prune_local
  if [ -n "$remote" ]; then
    if ! registry_rclone copyto "${dir}/${name}" "${remote%/}/${name}" >/dev/null 2>&1; then
      log_fail "copy to ${remote} failed (check opskit/owner/rclone.conf and the remote name)"
      return 1
    fi
    log_ok "copied off this machine: ${remote%/}/${name}"
    registry_prune_remote "$remote"
  else
    log_warn "kept on this machine only: add --to <remote:path> (e.g. b2:your-bucket/registry) to copy it off"
  fi
}

registry_prune_local() {
  local dir old
  dir="$(registry_backup_dir)"
  while IFS= read -r old; do
    [ -n "$old" ] && rm -f "${dir}/${old}"
  done < <(find "$dir" -maxdepth 1 -name 'registry-*.tar.gz.age' -printf '%f\n' | sort -r | tail -n "+$((REGISTRY_KEEP_LOCAL + 1))")
}

registry_prune_remote() {
  local remote="${1%/}" old
  while IFS= read -r old; do
    [ -z "$old" ] || registry_rclone deletefile "${remote}/${old}" >/dev/null 2>&1 || true
  done < <(registry_rclone lsf "$remote" --include 'registry-*.tar.gz.age' 2>/dev/null | sort -r | tail -n "+$((REGISTRY_KEEP_REMOTE + 1))")
}

# registry_fetch <latest|file|remote:path/file> <tmp dir>: prints the local archive path
registry_fetch() {
  local source="$1" tmp="$2"
  if [ "$source" = "latest" ]; then
    source="$(find "$(registry_backup_dir)" -maxdepth 1 -name 'registry-*.tar.gz.age' 2>/dev/null | sort | tail -n 1)"
    [ -n "$source" ] || { log_fail "no registry backup in $(registry_backup_dir)"; return 1; }
  fi
  if [ -f "$source" ]; then
    printf '%s' "$source"
    return 0
  fi
  if [[ "$source" == *:* ]] && registry_rclone copyto "$source" "${tmp}/archive.age" >/dev/null 2>&1; then
    printf '%s' "${tmp}/archive.age"
    return 0
  fi
  log_fail "registry backup not found: ${source}"
  return 1
}

# registry_restore <source> <overwrite true|false> <yes true|false>
registry_restore() {
  local source="$1" overwrite="$2" yes="$3" root tmp archive part existing=() aside
  root="$(registry_root)"
  [ -r "$(owner_age_identity)" ] || { log_fail "owner private key not readable ($(owner_age_identity)); restore needs it"; return 1; }
  tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  if ! archive="$(registry_fetch "$source" "$tmp")"; then
    rm -rf "$tmp"
    return 1
  fi
  mkdir -p "${tmp}/out"
  if ! age -d -i "$(owner_age_identity)" "$archive" | tar -C "${tmp}/out" -xzf -; then
    rm -rf "$tmp"
    log_fail "the archive does not decrypt with $(owner_age_identity) (wrong key or damaged file)"
    return 1
  fi
  for part in "${REGISTRY_PARTS[@]}"; do
    [ -d "${tmp}/out/${part}" ] || continue
    if [ -d "${root}/${part}" ] && [ -n "$(find "${root}/${part}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      existing+=("$part")
    fi
  done
  if [ "${#existing[@]}" -gt 0 ]; then
    if [ "$overwrite" != "true" ]; then
      rm -rf "$tmp"
      log_fail "${root} already has ${existing[*]}: nothing changed (add --overwrite --yes to replace them; the current ones are moved aside, not deleted)"
      return 1
    fi
    if ! confirm_destructive registry "$yes" "replace ${existing[*]} in ${root} from the backup"; then
      rm -rf "$tmp"
      return 1
    fi
    aside="${root}/.registry-before-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$aside"
    chmod 700 "$aside"
    for part in "${existing[@]}"; do
      mv "${root}/${part}" "${aside}/${part}"
    done
    log_ok "current ${existing[*]} moved aside to ${aside}"
  fi
  for part in "${REGISTRY_PARTS[@]}"; do
    [ -d "${tmp}/out/${part}" ] || continue
    rm -rf "${root:?}/${part}"
    mv "${tmp}/out/${part}" "${root}/${part}"
  done
  rm -rf "$tmp"
  log_ok "registry restored into ${root} from $(basename "$archive")"
}
