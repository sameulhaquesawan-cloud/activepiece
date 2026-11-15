#!/usr/bin/env bash
# opskit docs: the client's handover pack, one printable HTML file rendered by opskit/templates/docs/handover.jq
# from facts only (client.yaml, host yaml, notes.yaml, business profile, template manifests, the client's
# switched-on flows read with the read-only role). Never ids, secrets, run data or personal data from flows.
# Needs registry.sh, business.sh, clientdata.sh, flows.sh.

# docs_templates: [{name, description}] of the library, to explain flows built from a template
docs_templates() {
  local id
  while IFS= read -r id; do
    yq -o=json '{"name": .name, "description": .description}' "$(flows_dir)/${id}/template.yaml"
  done < <(flows_ids) | jq -s -c .
}

# docs_data <id> <active flows json>: everything the pack shows, as one JSON object
docs_data() {
  local id="$1" flows="$2" cfile hfile notes last_test
  cfile="$(client_file "$id")"
  hfile="$(host_file "$(yaml_get "$cfile" .host.name)")"
  notes="$(client_notes_file "$id")"
  last_test="$(tail -n 1 "$(client_dir "$id")/restore-tests.jsonl" 2>/dev/null || true)"
  jq -n \
    --argjson client "$(yq -o=json '{"name": .name, "domain": .domain, "contact": .contact, "timezone": .timezone,
        "response_hours": (.support.response_hours // 12), "included_hours": (.support.included_hours // 1),
        "backup_schedule": (.backup.schedule // "30 2 * * *"), "local_days": (.backup.retention_days.local // 14),
        "remote_days": (.backup.retention_days.remote // 30), "offsite": ((.backup.remote // "") != ""),
        "offboard_days": (.offboard_retention_days // 30), "channels": (.alerts.channels // [])}' "$cfile")" \
    --argjson host "$(yq -o=json '{"provider": (.provider // ""), "location": (.location // "")}' "$hfile")" \
    --argjson notes "$( [ -f "$notes" ] && yq -o=json '.' "$notes" || printf '{}')" \
    --argjson business "$(jq -n --arg name "$(business_get business_name)" --arg email "$(business_get support_email)" \
        --arg website "$(business_get website)" --arg phone "$(business_get phone)" --arg hours "$(business_get support_hours)" \
        --arg signature "$(business_get signature)" \
        '{name: $name, email: $email, website: $website, phone: $phone, hours: $hours, signature: $signature}')" \
    --argjson flows "$flows" \
    --argjson templates "$(docs_templates)" \
    --argjson restore "$( [ -n "$last_test" ] && printf '%s' "$last_test" || printf 'null')" \
    --arg generated "$(TZ="$(yaml_get "$cfile" .timezone UTC)" date +%Y-%m-%d)" \
    '{client: $client, host: $host, notes: $notes, business: $business, flows: $flows, templates: $templates,
      restore: $restore, generated: $generated}'
}

# docs_render <data json>: the HTML page
docs_render() {
  jq -r -f "${OPSKIT_ROOT}/templates/docs/handover.jq" <<< "$1"
}

# docs_problems <html file>: anything that must never reach a client
docs_problems() {
  local file="$1"
  grep -nE '\{\{|\$\{|null|undefined' "$file" | head -n 5 | sed 's/^/unfilled: /' || true
  grep -noE '(sk-[A-Za-z0-9]{16,}|xox[bp]-[A-Za-z0-9-]{10,}|AP_[A-Z_]+=|-----BEGIN)' "$file" | head -n 5 | sed 's/^/secret-like: /' || true
}

# docs_build <id>: writes clients/<id>/docs/handover.html
docs_build() {
  local id="$1" host flows dir out problems
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  flows="$(clientdata_active_flows "$host" "$id")" || { log_fail "could not read ${id}'s flows (stack running? read-only role installed by opskit deploy)"; return 1; }
  dir="$(client_dir "$id")/docs"
  mkdir -p "$dir"
  out="${dir}/handover.html"
  docs_render "$(docs_data "$id" "$flows")" > "${out}.tmp" || { rm -f "${out}.tmp"; log_fail "rendering the handover pack failed"; return 1; }
  problems="$(docs_problems "${out}.tmp")"
  if [ -n "$problems" ]; then
    rm -f "${out}.tmp"
    while IFS= read -r line; do log_fail "handover pack: ${line}"; done <<< "$problems"
    return 1
  fi
  mv "${out}.tmp" "$out"
  log_ok "handover pack for ${id}: ${out} ($(jq 'length' <<< "$flows") active flow(s)); open it in a browser, print to PDF, send it to the client"
}
