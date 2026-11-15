#!/usr/bin/env bash
# summary: render a client's handover pack (active flows + how to pause them, accounts, support, backups, privacy, Zapier move)

for lib in validate schema registry ssh host stack deploy verify business clientdata flows docs; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

docs_usage() {
  cat <<'USAGE'
Usage: opskit docs <client id>

Writes opskit/clients/<id>/docs/handover.html: one printable page for the client with their switched-on
flows (what each does, which accounts it uses, how to pause it), who owns which account, the support
promise, backups and where the data lives, the data & privacy note, the Zapier/Make move checklist and
what to do if something breaks. Reads the client's flows with the read-only database role; adds your
sentences from opskit/clients/<id>/notes.yaml and your details from opskit/owner/business.yaml.
Never includes ids, passwords, keys or data from runs. Changes nothing on the client.
USAGE
}

cmd_main() {
  case "${1:-}" in
    -h|--help) docs_usage; return 0 ;;
    ""|-*) docs_usage >&2; return 1 ;;
  esac
  [ "$#" -eq 1 ] || { docs_usage >&2; return 1; }
  require_client "$1" || return 1
  local notes
  notes="$(client_notes_file "$1")"
  if [ -f "$notes" ]; then
    validate_against_schema "${OPSKIT_ROOT}/schema/notes.schema.json" "$notes" >/dev/null \
      || die "notes.yaml of $1 is invalid: opskit/bin/opskit validate ${notes}"
  fi
  business_check || return 1
  docs_build "$1"
}
