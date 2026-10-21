#!/usr/bin/env bash
# opskit upgrade: version checks, release notes and pre-flight gates (read-only part, task 6.2).
# Registry and release-notes hosts can be pointed elsewhere for tests: OPSKIT_GHCR_URL,
# OPSKIT_DOCKERHUB_AUTH_URL, OPSKIT_DOCKERHUB_REGISTRY_URL, OPSKIT_UPSTREAM_RAW_URL.

UPGRADE_BACKUP_MAX_AGE_H=26
UPGRADE_RESTORE_TEST_MAX_AGE_D=35
UPGRADE_HOST_MIN_FREE_MB="${OPSKIT_UPGRADE_HOST_MIN_FREE_MB:-3072}"
UPGRADE_LOCAL_MIN_FREE_MB="${OPSKIT_UPGRADE_LOCAL_MIN_FREE_MB:-5120}"
UPGRADE_HOST_MIN_MEM_MB="${OPSKIT_UPGRADE_HOST_MIN_MEM_MB:-256}"
UPGRADE_MANIFEST_IN_IMAGE="/usr/src/app/packages/server/api/dist/src/migration-manifest.json"
UPGRADE_MIGRATIONS_IN_IMAGE="/usr/src/app/packages/server/api/dist/src/app/database/migration/postgres"

# upgrade_newer <a> <b>: true when version a is newer than b
upgrade_newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

# upgrade_tag_exists <repo> <tag>: the image tag is published (registry API, no download)
upgrade_tag_exists() {
  local repo="$1" tag="$2" base auth path token accept
  accept='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'
  case "$repo" in
    ghcr.io/*)
      path="${repo#ghcr.io/}"
      base="${OPSKIT_GHCR_URL:-https://ghcr.io}"
      auth="${base}/token?scope=repository:${path}:pull"
      ;;
    *)
      path="$repo"
      base="${OPSKIT_DOCKERHUB_REGISTRY_URL:-https://registry-1.docker.io}"
      auth="${OPSKIT_DOCKERHUB_AUTH_URL:-https://auth.docker.io}/token?service=registry.docker.io&scope=repository:${path}:pull"
      ;;
  esac
  token="$(curl -sS -m 20 "$auth" 2>/dev/null | jq -r '.token // empty' 2>/dev/null || true)"
  [ -n "$token" ] || return 2
  [ "$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
    "${base}/v2/${path}/manifests/${tag}" 2>/dev/null || true)" = "200" ]
}

# upgrade_release_notes <from> <to>: breaking-change headings Activepieces lists after <from> up to <to>
upgrade_release_notes() {
  local from="$1" to="$2" file
  file="$(mktemp)"
  if ! curl -sSf -m 30 -o "$file" \
    "${OPSKIT_UPSTREAM_RAW_URL:-https://raw.githubusercontent.com/activepieces/activepieces}/${to}/docs/install/reference/breaking-changes.mdx" 2>/dev/null; then
    rm -f "$file"
    return 1
  fi
  awk -v from="$from" -v to="$to" '
    function newer(a, b,   x, y, n, i) {
      n = split(a, x, "."); split(b, y, ".")
      for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) return 1; if (x[i] + 0 < y[i] + 0) return 0 }
      return 0
    }
    /^## / { section = substr($0, 4); keep = (section == "Unreleased") || (newer(section, from) && !newer(section, to)); next }
    keep && /^#### / && $0 !~ /What you need to do/ { print section ": " substr($0, 6) }
  ' "$file"
  rm -f "$file"
}

# upgrade_latest_backup <host> <id>: the newest status.json on the host (one JSON line) or nothing
upgrade_latest_backup() {
  local host="$1" id="$2" root
  root="$(host_root "$host")"
  # shellcheck disable=SC2016
  host_run "$host" sh -c 'for d in "$1"/*/; do [ -f "${d}status.json" ] && cat "${d}status.json" && echo; done; true' _ "${root}/backups/${id}" \
    | jq -c 'select(.backup)' 2>/dev/null | sort | tail -n 1
}

# upgrade_age_hours <UTC backup name YYYYmmddTHHMMSSZ>
upgrade_age_hours() {
  local name="$1" taken
  taken="$(date -u -d "${name:0:4}-${name:4:2}-${name:6:2}T${name:9:2}:${name:11:2}:${name:13:2}Z" +%s 2>/dev/null)" || return 1
  printf '%s' "$(( ($(date +%s) - taken) / 3600 ))"
}

# upgrade_preflight <id>: prints [ok]/[warn]/[fail]; returns 1 if a gate fails
upgrade_preflight() {
  local id="$1" cfile host latest name age remote_state remote last last_at last_days free failed=0
  cfile="$(client_file "$id")"
  host="$(yaml_get "$cfile" .host.name)"
  remote="$(yaml_get "$cfile" .backup.remote)"
  latest="$(upgrade_latest_backup "$host" "$id")"
  if [ -z "$latest" ]; then
    log_fail "no backup of ${id} on ${host}: run opskit backup ${id} first"
    failed=1
  else
    name="$(jq -r '.backup' <<< "$latest")"
    age="$(upgrade_age_hours "$name" || printf '?')"
    remote_state="$(jq -r '.remote // "?"' <<< "$latest")"
    if [ "$age" = "?" ] || [ "$age" -ge "$UPGRADE_BACKUP_MAX_AGE_H" ]; then
      log_fail "latest backup ${name} is older than ${UPGRADE_BACKUP_MAX_AGE_H} h: run opskit backup ${id} first"
      failed=1
    elif [ -n "$remote" ] && [ "$remote_state" != "ok" ]; then
      log_fail "latest backup ${name} is not off-server (remote: ${remote_state}): fix the off-server copy first"
      failed=1
    else
      log_ok "latest backup ${name} (${age} h old)$([ -n "$remote" ] && printf ', off-server copy ok')"
    fi
  fi
  last="$(tail -n 1 "$(client_dir "$id")/restore-tests.jsonl" 2>/dev/null || true)"
  if [ -z "$last" ]; then
    log_fail "${id} has no restore test yet: run opskit restore-test ${id} first"
    failed=1
  else
    last_at="$(jq -r '.at' <<< "$last")"
    last_days="$(( ($(date +%s) - $(date -u -d "$last_at" +%s)) / 86400 ))"
    if [ "$(jq -r '.result' <<< "$last")" != "pass" ]; then
      log_fail "last restore test (${last_at}) failed: fix it before upgrading"
      failed=1
    elif [ "$last_days" -gt "$UPGRADE_RESTORE_TEST_MAX_AGE_D" ]; then
      log_fail "last restore test is ${last_days} days old (max ${UPGRADE_RESTORE_TEST_MAX_AGE_D}): run opskit restore-test ${id}"
      failed=1
    else
      log_ok "last restore test passed (${last_at%%T*}, ${last_days} days ago)"
    fi
  fi
  upgrade_lock_check "$id" || failed=1
  if [ -r "$(owner_age_identity)" ]; then
    log_ok "owner key present here (staging decrypts the fresh backup)"
  else
    log_fail "owner age key not readable at $(owner_age_identity): set OPSKIT_OWNER_AGE_KEY (staging must decrypt the backup)"
    failed=1
  fi
  free="$(host_run "$host" df -Pm "$(host_root "$host")" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  if [ -z "$free" ] || [ "$free" -lt "$UPGRADE_HOST_MIN_FREE_MB" ]; then
    log_fail "${host}: ${free:-?} MB free disk (need ${UPGRADE_HOST_MIN_FREE_MB} MB for the new image and the pre-switch dump)"
    failed=1
  else
    log_ok "${host}: ${free} MB free disk"
  fi
  # shellcheck disable=SC2016
  free="$(host_run "$host" awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null)"
  if [ -z "$free" ] || [ "$free" -lt "$UPGRADE_HOST_MIN_MEM_MB" ]; then
    log_fail "${host}: ${free:-?} MB memory available (need ${UPGRADE_HOST_MIN_MEM_MB} MB to start the new version)"
    failed=1
  else
    log_ok "${host}: ${free} MB memory available"
  fi
  free="$(df -Pm "${TMPDIR:-/tmp}" | awk 'NR == 2 { print $4 }')"
  if [ "$free" -lt "$UPGRADE_LOCAL_MIN_FREE_MB" ]; then
    log_fail "this machine: ${free} MB free in ${TMPDIR:-/tmp} (staging needs ${UPGRADE_LOCAL_MIN_FREE_MB} MB)"
    failed=1
  else
    log_ok "this machine: ${free} MB free for the staging copy"
  fi
  return "$failed"
}

# upgrade_new_migrations <repo> <from> <to>: migrations in <to> that <from> lacks (both images must be local)
upgrade_new_migrations() {
  local repo="$1" from="$2" to="$3" a b
  docker image inspect "${repo}:${from}" >/dev/null 2>&1 && docker image inspect "${repo}:${to}" >/dev/null 2>&1 || return 1
  a="$(upgrade_image_migrations "${repo}:${from}")"
  b="$(upgrade_image_migrations "${repo}:${to}")"
  [ -n "$a" ] && [ -n "$b" ] || return 1
  comm -13 <(printf '%s\n' "$a") <(printf '%s\n' "$b")
}

upgrade_image_migrations() {
  docker run --rm --entrypoint cat "$1" "$UPGRADE_MANIFEST_IN_IMAGE" 2>/dev/null | jq -r '.[] | select(. != null)' | sort
}

# upgrade_breaking_migrations <image>: migrations the image marks as not undoable (breaking = true), as Name<timestamp>
upgrade_breaking_migrations() {
  # shellcheck disable=SC2016
  docker run --rm --entrypoint sh "$1" -c 'cd "$1" && grep -l "breaking = true" ./*.js' _ "$UPGRADE_MIGRATIONS_IN_IMAGE" 2>/dev/null \
    | sed -E 's|^\./([0-9]+)-(.*)\.js$|\2\1|' | sort
}

# upgrade_plan <id> <target tag>: everything the owner needs to decide; changes nothing
upgrade_plan() {
  local id="$1" to="$2" cfile repo from notes changes breaking rc line failed=0
  cfile="$(client_file "$id")"
  repo="$(yaml_get "$cfile" .image.repo ghcr.io/activepieces/activepieces)"
  from="$(yaml_get "$cfile" .image.tag)"
  log_info "Upgrade plan for ${id}: ${from} → ${to} (${repo})"
  if ! [[ "$to" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_fail "target ${to} is not a release version (x.y.z)"
    return 1
  fi
  if ! upgrade_newer "$to" "$from"; then
    log_fail "target ${to} is not newer than the running ${from} (downgrades are not upgrades)"
    return 1
  fi
  rc=0
  upgrade_tag_exists "$repo" "$to" || rc=$?
  case "$rc" in
    0) log_ok "image ${repo}:${to} is published" ;;
    2) log_fail "could not reach the registry for ${repo} (network?)"; failed=1 ;;
    *) log_fail "image ${repo}:${to} does not exist"; failed=1 ;;
  esac
  log_info "Breaking changes Activepieces lists after ${from} up to ${to}:"
  if notes="$(upgrade_release_notes "$from" "$to")"; then
    if [ -n "$notes" ]; then
      while IFS= read -r line; do log_info "  ${line}"; done <<< "$notes"
      ! grep -q '^Unreleased:' <<< "$notes" \
        || log_warn "items under \"Unreleased\" in ${to}'s notes may or may not be in ${to}: read them"
    else
      log_info "  none listed"
    fi
  else
    log_warn "could not read ${to}'s breaking-change notes: open https://github.com/activepieces/activepieces/releases/tag/${to}"
  fi
  if changes="$(upgrade_new_migrations "$repo" "$from" "$to")"; then
    log_info "Database: $(grep -c . <<< "$changes" || true) new migration(s) in ${to}"
    breaking="$(comm -12 <(printf '%s\n' "$changes") <(upgrade_breaking_migrations "${repo}:${to}") | grep . || true)"
    if [ -n "$breaking" ]; then
      log_warn "$(grep -c . <<< "$breaking") of them cannot be undone by Activepieces ($(paste -sd, <<< "$breaking")): a rollback restores the pre-switch backup (runs after the switch are lost)"
    fi
  else
    log_info "Database: schema changes are counted when both images are pulled (staging step)"
  fi
  upgrade_preflight "$id" || failed=1
  log_info "Expected downtime: 1–3 minutes while the app restarts; webhooks sent in that window may be lost."
  log_info "Checklist: docs/runbooks/upgrade-checklist.md (read it before running without --plan)."
  log_info "Plan only: nothing was changed."
  return "$failed"
}
