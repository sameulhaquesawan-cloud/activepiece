# Uptime Kuma heartbeats [[time "YYYY-MM-DD HH:MM:SS(.sss)" UTC, status]] → {up, down, uptime, down_periods}.
# Status 0 down, 1 up, 2 pending (counted as up, Kuma's rule), 3 maintenance (not counted).
# uptime: percent with 3 decimals, rounded down (never shows 100 when anything was down); null without beats.
def epoch: sub("\\.[0-9]+$"; "") | strptime("%Y-%m-%d %H:%M:%S") | mktime;
def iso: todate;
(map(select(.[1] == 1 or .[1] == 2)) | length) as $up
| (map(select(.[1] == 0)) | length) as $down
| {
    up: $up,
    down: $down,
    uptime: (if $up + $down == 0 then null else (($up * 100000 / ($up + $down)) | floor) / 1000 end),
    down_periods: (
      reduce .[] as $b ({open: null, last: null, periods: []};
        ($b[0] | epoch) as $t
        | if $b[1] == 0 then (if .open == null then .open = $t else . end) | .last = $t
          elif .open != null then .periods += [{start: .open, end: $t}] | .open = null
          else . end)
      | if .open != null then .periods += [{start: .open, end: .last}] else . end
      | .periods | map({start: (.start | iso), end: (.end | iso), minutes: (((.end - .start) / 60) | ceil | if . < 1 then 1 else . end)})
    )
  }
