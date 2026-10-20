#!/usr/bin/env bats

load helpers/common
load helpers/mock_http

setup_file() {
  export DETECT_PG="opskit-detect-test-$$"
  docker run -d --name "$DETECT_PG" -e POSTGRES_USER=activepieces -e POSTGRES_PASSWORD=test -e POSTGRES_DB=activepieces \
    --label com.docker.compose.project=acme --label com.docker.compose.service=postgres \
    pgvector/pgvector:0.8.0-pg14 >/dev/null
  local _
  for _ in $(seq 1 60); do
    docker exec "$DETECT_PG" pg_isready -U activepieces -d activepieces >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 2
  docker exec -i "$DETECT_PG" psql -q -U activepieces -d activepieces -v ON_ERROR_STOP=1 <<'SQL'
create table project (id varchar(21) primary key);
create table flow (id varchar(21) primary key, "projectId" varchar(21));
create table flow_version (id varchar(21) primary key, "flowId" varchar(21), "displayName" varchar);
create table flow_run (id varchar(21) primary key, "projectId" varchar(21), "flowId" varchar(21), "flowVersionId" varchar(21),
  environment varchar, status varchar, "finishTime" timestamptz, "failedStep" jsonb);
create table app_connection (id varchar(21) primary key);
insert into project values ('p1');
insert into flow values ('f1', 'p1'), ('f2', 'p1');
insert into flow_version values ('v1', 'f1', 'Lead capture'), ('v2', 'f2', 'Invoice reminder');
SQL
  docker exec -i "$DETECT_PG" psql -q -U activepieces -d activepieces -v ON_ERROR_STOP=1 -v db=activepieces \
    < "${OPSKIT_ROOT}/templates/readonly-role.sql"
}

teardown_file() {
  docker rm -f "$DETECT_PG" >/dev/null 2>&1 || true
}

setup() {
  ROOT="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme"
  cp "${OPSKIT_ROOT}/agent/alert.sh" "${OPSKIT_ROOT}/agent/detect-failed-runs.sh" "${OPSKIT_ROOT}/agent/digest.sh" "${ROOT}/agent/"
  cp -r "${OPSKIT_ROOT}/templates/alerts" "${ROOT}/agent/alerts"
  DETECT="${ROOT}/agent/detect-failed-runs.sh"
  start_mock_http
  export OPSKIT_TELEGRAM_API="$MOCK_URL"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${ROOT}/agent/alerts.conf"
  printf 'APP_URL=https://auto.acme.com\n' > "${ROOT}/clients/acme/alerts.conf"
  sql "delete from flow_run"
}

teardown() {
  stop_mock_http
  rm -rf "$ROOT"
}

sql() {
  docker exec -i "$DETECT_PG" psql -q -U activepieces -d activepieces -v ON_ERROR_STOP=1 -c "$1"
}

run_row() {
  local id="$1" flow="$2" env="$3" status="$4" step="${5:-null}"
  sql "insert into flow_run values ('${id}', 'p1', '${flow}', 'v${flow#f}', '${env}', '${status}', now(), ${step})"
}

texts() {
  mock_requests | jq -r .body | jq -r .text
}

# bats test_tags=docker
@test "first run only records the starting point" {
  run_row old1 f1 PRODUCTION FAILED
  run "$DETECT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"detector started"* ]]
  [ -s "${ROOT}/state/acme/detector.since" ]
  [ "$(mock_requests | jq -s length)" = "0" ]
}

# bats test_tags=docker
@test "a failed production run sends one alert with flow name, step, excerpt and run link" {
  "$DETECT" acme --root "$ROOT" >/dev/null
  run_row r1 f1 PRODUCTION FAILED "'{\"name\":\"step_4\",\"displayName\":\"Check email\",\"message\":\"{\\\"message\\\":\\\"Invalid email address\\\",\\\"stack\\\":\\\"at x\\\"}\"}'"
  run "$DETECT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(mock_requests | jq -s length)" = "1" ]
  [ "$(texts)" = "[CRITICAL] acme on $(hostname): Flow \"Lead capture\" failed (FAILED at step \"Check email\"): Invalid email address — run r1 — First action: Open the run, fix the failing step, then retry the failed runs
https://auto.acme.com/projects/p1/runs/r1" ]
}

# bats test_tags=docker
@test "several failures of one flow make one alert with a count; other flows alert separately" {
  "$DETECT" acme --root "$ROOT" >/dev/null
  run_row r1 f1 PRODUCTION FAILED
  run_row r2 f1 PRODUCTION TIMEOUT
  run_row r3 f2 PRODUCTION INTERNAL_ERROR
  run "$DETECT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(mock_requests | jq -s length)" = "2" ]
  texts | grep -q '2 runs of flow "Lead capture" failed (TIMEOUT)'
  texts | grep -q 'Flow "Invoice reminder" failed (INTERNAL_ERROR)'
}

# bats test_tags=docker
@test "a second detector run does not repeat alerts and a new failure within 30 min is de-duplicated" {
  "$DETECT" acme --root "$ROOT" >/dev/null
  run_row r1 f1 PRODUCTION FAILED
  "$DETECT" acme --root "$ROOT" >/dev/null
  "$DETECT" acme --root "$ROOT" >/dev/null
  [ "$(mock_requests | jq -s length)" = "1" ]
  run_row r2 f1 PRODUCTION FAILED
  run "$DETECT" acme --root "$ROOT"
  [[ "$output" == *"duplicate alert suppressed"* ]]
  [ "$(mock_requests | jq -s length)" = "1" ]
}

# bats test_tags=docker
@test "test runs, successful runs and all failure statuses are classified as SPEC 10.3 says" {
  "$DETECT" acme --root "$ROOT" >/dev/null
  run_row t1 f1 TESTING FAILED
  run_row s1 f1 PRODUCTION SUCCEEDED
  run_row c1 f1 PRODUCTION CANCELED
  local status_name i=0
  for status_name in FAILED INTERNAL_ERROR TIMEOUT MEMORY_LIMIT_EXCEEDED QUOTA_EXCEEDED LOG_SIZE_EXCEEDED; do
    i=$((i + 1))
    run_row "x${i}" f2 PRODUCTION "$status_name"
  done
  run "$DETECT" acme --root "$ROOT"
  [[ "$output" == *"6 failed runs since"* ]]
  texts | grep -q '6 runs of flow "Invoice reminder" failed'
  ! texts | grep -q 'Lead capture'
}

# bats test_tags=docker
@test "long or multi-line error messages are cut and flattened" {
  "$DETECT" acme --root "$ROOT" >/dev/null
  local long
  long="$(printf 'e%.0s' {1..500})"
  run_row r1 f1 PRODUCTION FAILED "jsonb_build_object('name','s','displayName','S','message', E'line1\\nline2 ${long}')"
  "$DETECT" acme --root "$ROOT" >/dev/null
  local text
  text="$(texts)"
  [[ "$text" == *"line1 line2 eee"* ]]
  [ "$(head -n 1 <<< "$text" | wc -c)" -lt 420 ]
}

# bats test_tags=docker
@test "the digest's 24 h run summary query works on the real schema with the read-only role" {
  run_row d1 f1 PRODUCTION FAILED
  run_row d2 f1 PRODUCTION SUCCEEDED
  run_row d3 f2 PRODUCTION SUCCEEDED
  run_row d4 f2 TESTING FAILED
  sql "insert into flow_run values ('old', 'p1', 'f1', 'v1', 'PRODUCTION', 'FAILED', now() - interval '25 hours', null)"
  run "${ROOT}/agent/digest.sh" acme --root "$ROOT" --now
  local text
  text="$(texts)"
  [[ "$text" == *"Runs (24 h): 3, failed: 1"* ]]
  [[ "$text" == *"  - Lead capture: 1 of 2 failed"* ]]
}

@test "detector needs a client id" {
  run "${OPSKIT_ROOT}/agent/detect-failed-runs.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}
