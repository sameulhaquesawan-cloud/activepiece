"[\(.severity | ascii_upcase)] \(.client) on \(.host): \(.what) — First action: \(.action)"
+ (if .link != "" then "\n\(.link)" else "" end)
+ (if (.body // "") != "" then "\n\n\(.body)" else "" end)
