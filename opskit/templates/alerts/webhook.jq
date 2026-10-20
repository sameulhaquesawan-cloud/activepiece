{client, severity, what, first_action: .action, host, at}
+ (if .link != "" then {link} else {} end)
+ (if (.body // "") != "" then {body} else {} end)
