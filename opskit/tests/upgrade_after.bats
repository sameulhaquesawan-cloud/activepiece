#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client acme acme.example.com
  # shellcheck source=/dev/null
  for lib in log validate schema registry ssh host stack deploy verify flows upgrade upgrade_after; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  CATALOG="$(full_catalog)"
  stack_psql() { printf '%s\n' "$CATALOG"; }
}

teardown() {
  rm -rf "$REG"
}

# full_catalog: every pinned piece of the library, supported from 0.80.0 with no upper bound
full_catalog() {
  upgrade_template_pieces | awk -F'|' '$4 == "" { print $2 "|" $3 "|0.80.0||OFFICIAL" }' | sort -u
}

@test "a catalog with every pinned piece: nothing to re-pin, follow-ups end the output" {
  run upgrade_after acme 0.92.3
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] every template's pinned pieces are in acme's catalog and support 0.92.3"* ]]
  [[ "$output" == *"[ok] our custom pieces on acme need nothing"* ]]
  [[ "$output" != *"Re-pin"* ]]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "  3. Watch the failed-run alerts for a day, then tell the client it is done (and what changed for them)." ]
}

@test "a pinned version missing or no longer supported lists the template to re-pin" {
  CATALOG="$(grep -v '^@activepieces/piece-gmail|' <<< "$CATALOG")"
  CATALOG+=$'\n'"$(upgrade_template_pieces | awk -F'|' '$2 == "@activepieces/piece-gmail" { print $2 "|" $3 "|0.80.0|0.92.0|OFFICIAL"; exit }')"
  run upgrade_after acme 0.92.3
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] template lead-capture: @activepieces/piece-gmail "*" supports releases 0.80.0–0.92.0, not 0.92.3"* ]]
  [[ "$output" == *"Re-pin templates "*"lead-capture"*" for 0.92.3 (flow.json + template.yaml), run CI"* ]]
  CATALOG="$(grep -v '^@activepieces/piece-slack|' <<< "$(full_catalog)")"
  run upgrade_after acme 0.92.3
  [[ "$output" == *"[warn] template ai-email-sorter: @activepieces/piece-slack "*" is not in acme's catalog"* ]]
  [[ "$output" == *"Re-pin templates ai-email-sorter for 0.92.3"* ]]
}

@test "our custom piece: an old install or one outside its releases asks for the idempotent re-install" {
  CATALOG+=$'\n''@opskit/piece-openai-compatible|0.0.9|0.80.0||CUSTOM'
  run upgrade_after acme 0.92.3
  [[ "$output" == *"[warn] @opskit/piece-openai-compatible 0.0.9 on acme (archive 0.1.0"* ]]
  [[ "$output" == *"Re-install our piece: opskit flows import ai-email-sorter acme"* ]]
  CATALOG="$(full_catalog)"$'\n''@opskit/piece-openai-compatible|0.1.0|0.80.0|0.92.0|CUSTOM'
  run upgrade_after acme 0.92.3
  [[ "$output" == *"supports 0.80.0–0.92.0): re-install it"* ]]
  CATALOG="$(full_catalog)"$'\n''@opskit/piece-openai-compatible|0.1.0|0.80.0||CUSTOM'
  run upgrade_after acme 0.92.3
  [[ "$output" != *"Re-install"* ]]
}

@test "an empty catalog (not synced yet) says when to look again and still lists the follow-ups" {
  CATALOG=""
  run upgrade_after acme 0.92.3
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] acme has no piece catalog yet"*"opskit upgrade acme --after in an hour"* ]]
  [[ "$output" == *"Follow-ups:"* ]]
}

@test "release bounds are inclusive and open when empty" {
  upgrade_supports 0.92.3 0.92.3 0.92.3
  upgrade_supports 0.92.3 "" ""
  ! upgrade_supports 0.92.3 0.93.0 ""
  ! upgrade_supports 0.92.3 "" 0.92.2
}

@test "opskit upgrade --after runs the follow-ups for the client's current tag, read-only" {
  local before
  before="$(sha256sum "${REG}/clients/acme/client.yaml")"
  run "$OPSKIT" upgrade acme --after
  [ "$status" -eq 0 ]
  [[ "$output" == *"After the upgrade of acme to $(yq -r .image.tag "${REG}/clients/acme/client.yaml"):"* ]]
  [[ "$output" == *"Follow-ups:"* ]]
  [ "$(sha256sum "${REG}/clients/acme/client.yaml")" = "$before" ]
}
