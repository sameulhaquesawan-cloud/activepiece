#!/usr/bin/env bash
# Read-only facts from a client's Activepieces database for handover packs and care reports, always through
# the opskit_ro role (SELECT on flow, flow_version, flow_run, project only; ASSUMPTIONS #13, #29).
# Needs deploy.sh (stack_compose) and verify.sh (stack_service_container).

CLIENTDATA_FAILED="'FAILED', 'INTERNAL_ERROR', 'TIMEOUT', 'MEMORY_LIMIT_EXCEEDED', 'QUOTA_EXCEEDED', 'LOG_SIZE_EXCEEDED'"

# clientdata_query <host> <id> <psql -v assignments...>: SQL on stdin, one JSON value out
clientdata_query() {
  local host="$1" id="$2" pg
  shift 2
  pg="$(stack_service_container "$host" "$id" postgres)"
  [ -n "$pg" ] || { log_fail "postgres of ${id} is not running"; return 1; }
  # shellcheck disable=SC2016
  host_run "$host" docker exec -i "$pg" sh -c 'psql -U opskit_ro -d "$POSTGRES_DB" -X -q -v ON_ERROR_STOP=1 -tA "$@"' _ "$@"
}

# clientdata_active_flows <host> <id>: JSON array of switched-on flows:
# [{name, trigger_piece, trigger, pieces: [...], last_run}] sorted by name
clientdata_active_flows() {
  clientdata_query "$1" "$2" <<'SQL'
select coalesce(json_agg(f order by f.name), '[]'::json) from (
  select v."displayName" as name,
         v.trigger->'settings'->>'pieceName' as trigger_piece,
         v.trigger->'settings'->>'triggerName' as trigger,
         (select coalesce(json_agg(distinct p #>> '{}' order by p #>> '{}'), '[]'::json)
            from jsonb_path_query(v.trigger, 'strict $.**.pieceName') p) as pieces,
         (select max(r.created) from flow_run r where r."flowId" = fl.id and r.environment = 'PRODUCTION') as last_run
  from flow fl
  join flow_version v on v.id = fl."publishedVersionId"
  where fl.status = 'ENABLED'
) f;
SQL
}

# clientdata_month_runs <host> <id> <YYYY-MM> <time zone>: JSON array per flow (production runs created in
# that calendar month of the time zone; archived runs included):
# [{name, total, succeeded, failed, other}] sorted by name; flows deleted since then are gone (cascade)
clientdata_month_runs() {
  local host="$1" id="$2" month="$3" tz="$4"
  [[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || { log_fail "month must be YYYY-MM: ${month}"; return 1; }
  clientdata_query "$host" "$id" -v "month=${month}" -v "tz=${tz}" <<SQL
select coalesce(json_agg(m order by m.name, m.flow_id), '[]'::json) from (
  select r."flowId" as flow_id,
         coalesce(min(pv."displayName"), max(rv."displayName"), r."flowId") as name,
         count(*) as total,
         count(*) filter (where r.status = 'SUCCEEDED') as succeeded,
         count(*) filter (where r.status in (${CLIENTDATA_FAILED})) as failed,
         count(*) filter (where r.status <> 'SUCCEEDED' and r.status not in (${CLIENTDATA_FAILED})) as other
  from flow_run r
  join flow fl on fl.id = r."flowId"
  left join flow_version pv on pv.id = fl."publishedVersionId"
  left join flow_version rv on rv.id = r."flowVersionId"
  where r.environment = 'PRODUCTION'
    and r.created >= ((:'month' || '-01')::timestamp at time zone :'tz')
    and r.created < (((:'month' || '-01')::timestamp + interval '1 month') at time zone :'tz')
  group by r."flowId"
) m;
SQL
}
