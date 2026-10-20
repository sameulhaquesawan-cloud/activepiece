#!/usr/bin/env bats

load helpers/common

SQL="${OPSKIT_ROOT}/templates/readonly-role.sql"

@test "read-only role has no password, no special powers and a read-only default" {
  grep -q 'PASSWORD NULL' "$SQL"
  grep -q 'NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS' "$SQL"
  grep -q 'default_transaction_read_only = on' "$SQL"
  ! grep -qiE 'password +'"'" "$SQL"
}

@test "read-only role is only granted SELECT on the detector tables" {
  [ "$(grep -ciE '^grant ' "$SQL")" = "3" ]
  grep -qx 'GRANT SELECT ON flow, flow_version, flow_run, project TO opskit_ro;' "$SQL"
  ! grep -qiE 'grant (insert|update|delete|all|truncate)' "$SQL"
  ! grep -qi 'app_connection' "$SQL"
}

@test "re-running the role setup resets drifted grants" {
  grep -qx 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM opskit_ro;' "$SQL"
  [ "$(grep -n 'REVOKE ALL' "$SQL" | cut -d: -f1)" -lt "$(grep -n 'GRANT SELECT' "$SQL" | cut -d: -f1)" ]
}
