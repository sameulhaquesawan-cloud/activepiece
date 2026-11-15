#!/usr/bin/env bash
# opskit upgrade, follow-ups after a successful switch (task 6.9). Read-only look at the client's own
# piece catalog (table piece_metadata: official pieces synced from the Activepieces cloud at start and
# hourly, plus our custom pieces): is each template's pinned piece version there and supported by the
# new release, is our custom piece still installed. Then the owner's follow-up list. Never changes client
# flows and never fails the upgrade. Needs flows.sh, verify.sh (stack_psql), upgrade.sh (upgrade_newer).

# upgrade_supports <release> <min> <max>: min <= release <= max (an empty bound is open)
upgrade_supports() {
  local release="$1" min="$2" max="$3"
  { [ -z "$min" ] || [ "$min" = "$release" ] || upgrade_newer "$release" "$min"; } \
    && { [ -z "$max" ] || [ "$max" = "$release" ] || upgrade_newer "$max" "$release"; }
}

# upgrade_template_pieces: "<template>|<name>|<version>|<custom dir or empty>" for every library template
upgrade_template_pieces() {
  local template
  while IFS= read -r template; do
    yq -r '.pieces[] | [.name, .version, .custom // ""] | join("|")' "$(flows_dir)/${template}/template.yaml" \
      | sed "s/^/${template}|/"
  done < <(flows_ids)
}

# upgrade_after <id> <release>: prints [ok]/[warn] lines and the numbered follow-ups; always returns 0
upgrade_after() {
  local id="$1" release="$2" host catalog template name version custom row installed min max repin="" reinstall="" n=1
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  log_info "After the upgrade of ${id} to ${release}:"
  catalog="$(stack_psql "$host" "$id" "select name || '|' || version || '|' || coalesce(\"minimumSupportedRelease\", '') || '|' || coalesce(\"maximumSupportedRelease\", '') || '|' || \"pieceType\" from piece_metadata" 2>/dev/null || true)"
  if [ -z "$catalog" ]; then
    log_warn "${id} has no piece catalog yet (it syncs from the Activepieces cloud after a start, then hourly): run opskit upgrade ${id} --after in an hour"
  else
    while IFS='|' read -r template name version custom; do
      if [ -n "$custom" ]; then
        row="$(awk -F'|' -v n="$name" '$1 == n && $5 == "CUSTOM"' <<< "$catalog" | sort -t'|' -k2,2V | tail -n 1)"
        [ -n "$row" ] || continue
        IFS='|' read -r _ installed min max _ <<< "$row"
        if [ "$installed" != "$version" ] || ! upgrade_supports "$release" "$min" "$max"; then
          [[ "$reinstall" == *"${template}"* ]] || reinstall+="${template} "
          log_warn "${name} ${installed} on ${id} (archive ${version}, supports ${min:-any}–${max:-any}): re-install it"
        fi
        continue
      fi
      row="$(awk -F'|' -v n="$name" -v v="$version" '$1 == n && $2 == v' <<< "$catalog" | head -n 1)"
      if [ -z "$row" ]; then
        log_warn "template ${template}: ${name} ${version} is not in ${id}'s catalog"
        [[ " ${repin}" == *" ${template} "* ]] || repin+="${template} "
        continue
      fi
      IFS='|' read -r _ _ min max _ <<< "$row"
      if ! upgrade_supports "$release" "$min" "$max"; then
        log_warn "template ${template}: ${name} ${version} supports releases ${min:-any}–${max:-any}, not ${release}"
        [[ " ${repin}" == *" ${template} "* ]] || repin+="${template} "
      fi
    done < <(upgrade_template_pieces | sort -u)
    [ -n "$repin" ] || log_ok "every template's pinned pieces are in ${id}'s catalog and support ${release}"
    [ -n "$reinstall" ] || log_ok "our custom pieces on ${id} need nothing (not installed, or current and supported)"
  fi
  log_info "Follow-ups:"
  log_info "  $((n++)). Open ${id}'s builder: log in, open two flows, look at the last runs."
  log_info "  $((n++)). Test what the breaking-change notes in the plan touched, if ${id} uses it."
  if [ -n "$reinstall" ]; then
    log_info "  $((n++)). Re-install our piece: opskit flows import ${reinstall%% *} ${id} (admin password; existing flows are left alone)."
  fi
  if [ -n "$repin" ]; then
    log_info "  $((n++)). Re-pin templates ${repin% } for ${release} (flow.json + template.yaml), run CI, then re-check flows of ${id} built from them."
  fi
  log_info "  $((n++)). Watch the failed-run alerts for a day, then tell the client it is done (and what changed for them)."
  return 0
}
