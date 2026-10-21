# run_code <template> <step name> <inputs json>: runs a template's code step with node like the
# Activepieces engine does (ES module exporting `code`); prints the JSON result or the thrown message.
run_code() {
  local dir="${OPSKIT_ROOT}/flows/$1" script
  script="$(mktemp --suffix .mjs)"
  jq -r --arg s "$2" '[.. | objects | select(.name? == $s and .type? == "CODE")][0].settings.sourceCode.code' "${dir}/flow.json" > "$script"
  cat >> "$script" <<'JS'

try {
  console.log(JSON.stringify(await code(JSON.parse(process.argv[2]))));
} catch (error) {
  console.log('THROWN: ' + error.message);
  process.exitCode = 3;
}
JS
  node "$script" "$3"
  local status=$?
  rm -f "$script"
  return "$status"
}
