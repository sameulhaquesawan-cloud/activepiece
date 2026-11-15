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

@test "without a profile the placeholders are used and the check says so" {
  [ "$(business_get business_name)" = "YourBrand" ]
  [ "$(business_get support_email)" = "support@yourbrand.example" ]
  for lib in schema; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  run business_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] no owner business profile at ${REG}/owner/business.yaml: placeholders like \"YourBrand\" are used"* ]]
}

@test "the owner's own values win, missing fields fall back" {
  mkdir -p "${REG}/owner"
  printf 'business_name: Acme Automation\nsupport_email: help@acme-automation.example\n' > "${REG}/owner/business.yaml"
  [ "$(business_get business_name)" = "Acme Automation" ]
  [ "$(business_get support_hours 2>/dev/null)" = "Mon–Fri 9:00–17:00 CET" ]
}
