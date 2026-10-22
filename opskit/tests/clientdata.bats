#!/usr/bin/env bats

load helpers/common

# A fixture database with hand-counted runs (October 2026, client time zone Europe/Berlin = UTC+2 until
# 25 Oct, UTC+1 after): the month starts 2026-09-30 22:00 UTC and ends 2026-10-31 23:00 UTC.
setup_file() {
  export CD_PG="opskit-clientdata-test-$$"
  docker run -d --name "$CD_PG" -e POSTGRES_USER=activepieces -e POSTGRES_PASSWORD=test -e POSTGRES_DB=activepieces \
    pgvector/pgvector:0.8.0-pg14 >/dev/null
  local _
  for _ in $(seq 1 60); do
    docker exec "$CD_PG" pg_isready -U activepieces -d activepieces >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 2
  docker exec -i "$CD_PG" psql -q -U activepieces -d activepieces -v ON_ERROR_STOP=1 <<'SQL'
create table project (id varchar(21) primary key);
create table flow (id varchar(21) primary key, "projectId" varchar(21), status varchar, "publishedVersionId" varchar(21));
create table flow_version (id varchar(21) primary key, "flowId" varchar(21), "displayName" varchar, trigger jsonb);
create table flow_run (id varchar(21) primary key, "projectId" varchar(21), "flowId" varchar(21), "flowVersionId" varchar(21),
  environment varchar, status varchar, created timestamptz, "archivedAt" varchar);
create table app_connection (id varchar(21) primary key, value jsonb);
insert into project values ('p1');
insert into flow values ('f1', 'p1', 'ENABLED', 'v1b'), ('f2', 'p1', 'DISABLED', 'v2'), ('f3', 'p1', 'ENABLED', 'v3'), ('f4', 'p1', 'DISABLED', null);
insert into flow_version values
  ('v1a', 'f1', 'Lead capture (old name)', null),
  ('v1b', 'f1', 'Lead capture', '{"settings": {"pieceName": "@activepieces/piece-webhook", "triggerName": "catch_webhook"},
     "nextAction": {"settings": {"pieceName": "@activepieces/piece-google-sheets"},
       "nextAction": {"settings": {"pieceName": "@activepieces/piece-gmail"}, "nextAction": {"settings": {"pieceName": "@activepieces/piece-gmail"}}}}}'),
  ('v2', 'f2', 'Invoice reminder', '{"settings": {"pieceName": "@activepieces/piece-schedule", "triggerName": "every_day"}}'),
  ('v3', 'f3', 'AI email sorter', '{"settings": {"pieceName": "@activepieces/piece-gmail", "triggerName": "gmail_new_email_received"}}'),
  ('v4', 'f4', 'Draft only', null);
insert into flow_run values
  ('r01', 'p1', 'f1', 'v1a', 'PRODUCTION', 'SUCCEEDED', '2026-09-30 21:59:59+00', null),
  ('r02', 'p1', 'f1', 'v1a', 'PRODUCTION', 'SUCCEEDED', '2026-09-30 22:00:00+00', null),
  ('r03', 'p1', 'f1', 'v1b', 'PRODUCTION', 'FAILED', '2026-10-10 10:00:00+00', null),
  ('r04', 'p1', 'f1', 'v1b', 'PRODUCTION', 'SUCCEEDED', '2026-10-15 10:00:00+00', '2026-10-16T00:00:00Z'),
  ('r05', 'p1', 'f1', 'v1b', 'TESTING', 'SUCCEEDED', '2026-10-15 11:00:00+00', null),
  ('r06', 'p1', 'f1', 'v1b', 'PRODUCTION', 'INTERNAL_ERROR', '2026-10-31 22:59:59+00', null),
  ('r07', 'p1', 'f1', 'v1b', 'PRODUCTION', 'SUCCEEDED', '2026-10-31 23:00:00+00', null),
  ('r08', 'p1', 'f2', 'v2', 'PRODUCTION', 'SUCCEEDED', '2026-10-05 06:00:00+00', null),
  ('r09', 'p1', 'f2', 'v2', 'PRODUCTION', 'TIMEOUT', '2026-10-06 06:00:00+00', null),
  ('r10', 'p1', 'f2', 'v2', 'PRODUCTION', 'CANCELED', '2026-10-07 06:00:00+00', null),
  ('r11', 'p1', 'f3', 'v3', 'PRODUCTION', 'RUNNING', '2026-10-20 06:00:00+00', null),
  ('r12', 'p1', 'f4', 'v4', 'PRODUCTION', 'SUCCEEDED', '2026-10-20 06:00:00+00', null);
SQL
  docker exec -i "$CD_PG" psql -q -U activepieces -d activepieces -v ON_ERROR_STOP=1 -v db=activepieces \
    < "${OPSKIT_ROOT}/templates/readonly-role.sql"
}

teardown_file() {
  docker rm -f "$CD_PG" >/dev/null 2>&1 || true
}

setup() {
  for lib in log clientdata; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  stack_service_container() { printf '%s' "$CD_PG"; }
  host_run() { shift; "$@"; }
}

# bats test_tags=docker
@test "monthly runs per flow match the hand count, in the client's time zone, production only" {
  run clientdata_month_runs h acme 2026-10 Europe/Berlin
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | {name, total, succeeded, failed, other}]' <<< "$output")" = \
    '[{"name":"AI email sorter","total":1,"succeeded":0,"failed":0,"other":1},{"name":"Draft only","total":1,"succeeded":1,"failed":0,"other":0},{"name":"Invoice reminder","total":3,"succeeded":1,"failed":1,"other":1},{"name":"Lead capture","total":4,"succeeded":2,"failed":2,"other":0}]' ]
}

# bats test_tags=docker
@test "the same data in UTC moves the edge runs to the other months" {
  run clientdata_month_runs h acme 2026-10 UTC
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | select(.name == "Lead capture") | {total, succeeded, failed}][0]' <<< "$output")" = '{"total":4,"succeeded":2,"failed":2}' ]
  run clientdata_month_runs h acme 2026-09 Europe/Berlin
  [ "$(jq -c '[.[] | {name, total}]' <<< "$output")" = '[{"name":"Lead capture","total":1}]' ]
  run clientdata_month_runs h acme 2026-12 Europe/Berlin
  [ "$output" = "[]" ]
}

# bats test_tags=docker
@test "active flows: switched-on flows only, with trigger and every piece used, never an id" {
  run clientdata_active_flows h acme
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | {name, trigger_piece, trigger, pieces}]' <<< "$output")" = \
    '[{"name":"AI email sorter","trigger_piece":"@activepieces/piece-gmail","trigger":"gmail_new_email_received","pieces":["@activepieces/piece-gmail"]},{"name":"Lead capture","trigger_piece":"@activepieces/piece-webhook","trigger":"catch_webhook","pieces":["@activepieces/piece-gmail","@activepieces/piece-google-sheets","@activepieces/piece-webhook"]}]' ]
  [ "$(jq -r '.[] | select(.name == "Lead capture") | .last_run' <<< "$output")" = "2026-10-31T23:00:00+00:00" ]
  [[ "$output" != *'"id"'* ]]
}

# bats test_tags=docker
@test "only the read-only role is used: it cannot read connections" {
  run clientdata_query h acme <<< "select count(*) from app_connection"
  [ "$status" -ne 0 ]
  [[ "$output" == *"permission denied"* ]]
}

# bats test_tags=docker
@test "a bad month is refused before any query" {
  run clientdata_month_runs h acme 2026-13 UTC
  [ "$status" -eq 1 ]
  [[ "$output" == *"month must be YYYY-MM"* ]]
}
