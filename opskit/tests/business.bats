#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  for lib in log registry business; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
}

teardown() {
  rm -rf "$REG"
}

@test "without a profile the placeholders are used and the owner is warned once" {
  run bash -c 'OPSKIT_ROOT="$0"; for lib in log registry business; do source "$0/lib/${lib}.sh"; done; business_get business_name; echo; business_get support_email' "$OPSKIT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YourBrand"* ]]
  [[ "$output" == *"support@yourbrand.example"* ]]
  [ "$(grep -c 'owner business profile incomplete' <<< "$output")" = "1" ]
}

@test "the owner's own values win, missing fields fall back" {
  mkdir -p "${REG}/owner"
  printf 'business_name: Acme Automation\nsupport_email: help@acme-automation.example\n' > "${REG}/owner/business.yaml"
  [ "$(business_get business_name)" = "Acme Automation" ]
  [ "$(business_get support_hours 2>/dev/null)" = "Mon–Fri 9:00–17:00 CET" ]
}
