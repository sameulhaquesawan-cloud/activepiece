# Stub variant of a filled template for the selftest (opskit/lib/e2e_flows.sh): piece steps of $pieces become
# code steps returning their input or $stubs[step]; a non-webhook trigger becomes a webhook ($webhookVersion)
# and trigger references point at the webhook body. Input: a filled export ({name, flows}); output: an
# IMPORT_FLOW request body.
def stub_code($stubs; $name):
  if ($stubs | has($name)) then "export const code = async () => (" + ($stubs[$name] | tojson) + ");"
  else "export const code = async (inputs) => inputs;" end;
def stub_step($pieces; $stubs):
  if type == "object" and .type == "PIECE" and (.settings.pieceName as $p | $pieces | index($p)) != null then
    .name as $n |
    {name, displayName: (.displayName + " [stub]"), type: "CODE", valid: true, lastUpdatedDate,
     settings: {sourceCode: {packageJson: "{}", code: stub_code($stubs; $n)},
       input: (if ($stubs | has($n)) then {} else .settings.input end),
       errorHandlingOptions: .settings.errorHandlingOptions}}
    + (if has("nextAction") then {nextAction} else {} end)
  else . end;
def retarget_trigger:
  walk(if type == "string" then gsub("trigger\\['(?<k>[^']+)'\\]"; "trigger['body']['\(.k)']") | gsub("trigger\\.(?<k>[A-Za-z_]+)"; "trigger.body.\(.k)") else . end);
.flows[0] as $f
| ($f.trigger.settings.pieceName == "@activepieces/piece-webhook") as $webhook
| {displayName: ($f.displayName + " (opskit stub test)"), schemaVersion: $f.schemaVersion, notes: [],
   trigger: ($f.trigger | walk(stub_step($pieces; $stubs))
     | if $webhook then . else (.nextAction | retarget_trigger) as $next
       | {name: "trigger", displayName: "Test webhook [stub]", type: "PIECE_TRIGGER", valid: true, lastUpdatedDate,
          settings: {pieceName: "@activepieces/piece-webhook", pieceVersion: $webhookVersion, triggerName: "catch_webhook",
            propertySettings: {}, input: {authType: "none", authFields: {}}}} + (if $next then {nextAction: $next} else {} end) end)}
