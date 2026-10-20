"[\(.severity | ascii_upcase)] \(.client) on \(.host): \(.what) — First action: \(.action)"
+ (if .link != "" then "\n\(.link)" else "" end)
