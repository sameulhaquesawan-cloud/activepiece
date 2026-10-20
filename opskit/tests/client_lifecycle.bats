#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  FILE="${REG}/clients/demo/client.yaml"
  STUB="$(mktemp -d)"
  cat > "${STUB}/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "${STUB}/calls"
case "\$*" in
  *" ps -q app"*) echo cid ;;
  "inspect -f {{.State.Health.Status}} cid") echo healthy ;;
esac
exit 0
EOF
  chmod +x "${STUB}/docker"
  export PATH="${STUB}:${PATH}"
}

teardown() {
  rm -rf "$REG" "$STUB"
}

status_of() {
  yq -r .status "$FILE"
}

@test "pause needs a deployed client, stops it and records it" {
  run "$OPSKIT" client pause demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"only deployed clients can be paused"* ]]
  yq -i '.status = "deployed"' "$FILE"
  run "$OPSKIT" client pause demo
  [ "$status" -eq 0 ]
  [ "$(status_of)" = "paused" ]
  grep -q -- "compose -p demo .* stop" "${STUB}/calls"
}

@test "resume starts a paused client and waits for health" {
  yq -i '.status = "paused"' "$FILE"
  run "$OPSKIT" client resume demo
  [ "$status" -eq 0 ]
  [ "$(status_of)" = "deployed" ]
  grep -q -- "compose -p demo .* start" "${STUB}/calls"
  [ "$(yq -r '.history[-1].event' "$FILE")" = "resumed" ]
}

@test "offboard requires --yes and the typed id" {
  yq -i '.status = "deployed"' "$FILE"
  run "$OPSKIT" client offboard demo
  [ "$status" -eq 1 ]
  run bash -c "echo nope | '$OPSKIT' client offboard demo --yes"
  [ "$status" -eq 1 ]
  [ "$(status_of)" = "deployed" ]
  [ ! -e "${STUB}/calls" ]
}

@test "offboard stops the stack, removes the site and dates it" {
  yq -i '.status = "deployed"' "$FILE"
  run bash -c "echo demo | '$OPSKIT' client offboard demo --yes"
  [ "$status" -eq 0 ]
  [ "$(status_of)" = "offboarded" ]
  [ "$(yq -r .offboarded_at "$FILE")" = "$(date -u +%Y-%m-%d)" ]
  grep -q -- "compose -p demo .* stop" "${STUB}/calls"
  grep -q "caddy reload" "${STUB}/calls"
  ! grep -q -- "down -v" "${STUB}/calls"
}

@test "purge is refused before offboarding and before the retention date" {
  run bash -c "echo demo | '$OPSKIT' client offboard demo --purge --yes"
  [ "$status" -eq 1 ]
  [[ "$output" == *"purge only after offboarding"* ]]
  yq -i ".status = \"offboarded\" | .offboarded_at = \"$(date -u +%Y-%m-%d)\"" "$FILE"
  run bash -c "echo demo | '$OPSKIT' client offboard demo --purge --yes"
  [ "$status" -eq 1 ]
  [[ "$output" == *"retention not over"* ]]
  [ ! -e "${STUB}/calls" ]
}

@test "purge after retention deletes volumes only with confirmation" {
  yq -i '.status = "offboarded" | .offboarded_at = "2020-01-01"' "$FILE"
  run "$OPSKIT" client offboard demo --purge
  [ "$status" -eq 1 ]
  [ ! -e "${STUB}/calls" ]
  run bash -c "echo demo | '$OPSKIT' client offboard demo --purge --yes"
  [ "$status" -eq 0 ]
  grep -q -- "compose -p demo .* down -v --remove-orphans" "${STUB}/calls"
  [ "$(yq -r '.history[-1].event' "$FILE")" = "purged" ]
}
