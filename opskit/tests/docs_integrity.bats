#!/usr/bin/env bats

load helpers/common

DOCS="${BATS_TEST_DIRNAME}/../../docs"

@test "SPEC keeps all its sections" {
  [ "$(wc -l < "${DOCS}/SPEC.md")" -ge 250 ]
  for heading in "## 0. Instructions" "## 3. Architecture rules" "## 17. Build phases" "### Phase 9" "## Appendix C"; do
    grep -qF "$heading" "${DOCS}/SPEC.md"
  done
}

@test "decision log has every ADR from 001 in order" {
  local numbers expected
  numbers="$(grep -oE '^### ADR-[0-9]{3}' "${DOCS}/DECISIONS.md" | grep -oE '[0-9]{3}' | tr '\n' ' ')"
  expected="$(seq -f '%03g' 1 "$(grep -cE '^### ADR-[0-9]{3}' "${DOCS}/DECISIONS.md")" | tr '\n' ' ')"
  [ "$numbers" = "$expected" ]
  [ "$(grep -cE '^### ADR-' "${DOCS}/DECISIONS.md")" -ge 14 ]
}

@test "assumption rows are numbered 1..N without gaps" {
  local numbers expected
  numbers="$(awk -F'|' '/^\| [0-9]+ \|/ {gsub(/ /, "", $2); print $2}' "${DOCS}/ASSUMPTIONS.md" | tr '\n' ' ')"
  expected="$(seq 1 "$(grep -cE '^\| [0-9]+ \|' "${DOCS}/ASSUMPTIONS.md")" | tr '\n' ' ')"
  [ "$numbers" = "$expected" ]
  [ "$(grep -cE '^\| [0-9]+ \|' "${DOCS}/ASSUMPTIONS.md")" -ge 7 ]
}

@test "progress and ledger files keep their structure" {
  grep -qF "## Next steps" "${DOCS}/PROGRESS.md"
  grep -qF "## Known issues" "${DOCS}/PROGRESS.md"
  grep -qF "| Pinned release tag |" "${DOCS}/UPSTREAM_CHANGES.md"
  grep -qF "## Patch ledger" "${DOCS}/UPSTREAM_CHANGES.md"
}
