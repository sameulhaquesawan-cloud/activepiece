#!/usr/bin/env bats

load helpers/common

setup() {
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/confirm.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
}

@test "destructive action without --yes is refused" {
  run confirm_destructive acme false "delete stack"
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-run with --yes"* ]]
}

@test "--yes alone is not enough: no typed id refuses" {
  run confirm_destructive acme true "delete stack" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing was changed"* ]]
}

@test "--yes with a wrong typed id refuses" {
  run confirm_destructive acme true "delete stack" <<< "acme2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match acme"* ]]
}

@test "--yes with the correct typed id confirms" {
  run confirm_destructive acme true "delete stack" <<< "acme"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] confirmed: delete stack"* ]]
}

@test "slugs" {
  for ok in acme a1 acme-dental client-2026; do is_slug "$ok"; done
  for bad in "" a Acme 1acme acme- -acme "ac me" acme--x "$(printf 'a%.0s' {1..40})"; do
    run is_slug "$bad"
    [ "$status" -eq 1 ]
  done
}

@test "domains" {
  for ok in auto.client.com a.b.co status.my-brand.io; do is_domain "$ok"; done
  for bad in "" localhost client..com -bad.com bad-.com "space .com" UPPER.com http://x.com; do
    run is_domain "$bad"
    [ "$status" -eq 1 ]
  done
}

@test "emails" {
  for ok in ops@example.com first.last+tag@sub.example.co; do is_email "$ok"; done
  for bad in "" plain @example.com a@ a@b "a b@example.com"; do
    run is_email "$bad"
    [ "$status" -eq 1 ]
  done
}

@test "ports and positive integers" {
  for ok in 1 80 8080 65535; do is_port "$ok"; done
  for bad in 0 -1 65536 08 abc ""; do
    run is_port "$bad"
    [ "$status" -eq 1 ]
  done
  is_positive_int 3
  run is_positive_int 0
  [ "$status" -eq 1 ]
}
