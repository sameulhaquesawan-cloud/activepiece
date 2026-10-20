#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
  source "${OPSKIT_ROOT}/lib/schema.sh"
  source "${OPSKIT_ROOT}/lib/registry.sh"
  source "${OPSKIT_ROOT}/lib/render.sh"
  source "${OPSKIT_ROOT}/lib/secrets.sh"
  source "${OPSKIT_ROOT}/lib/stack.sh"
  source "${OPSKIT_ROOT}/lib/ssh.sh"
  source "${OPSKIT_ROOT}/lib/host.sh"
  source "${OPSKIT_ROOT}/lib/deploy.sh"
  FILE="${REG}/clients/demo/client.yaml"
}

teardown() {
  rm -rf "$REG"
}

deployed_events() {
  yq -r '[.history[] | select(.event == "deployed")] | length' "$FILE"
}

@test "first deploy marks the client deployed and records the tag" {
  deploy_record demo
  [ "$(yq -r .status "$FILE")" = "deployed" ]
  [ "$(deployed_events)" = "1" ]
  [ "$(yq -r '.history[-1].tag' "$FILE")" = "0.92.3" ]
}

@test "re-deploying the same tag adds no history; a new tag does" {
  deploy_record demo
  deploy_record demo
  [ "$(deployed_events)" = "1" ]
  yq -i '.image.tag = "0.93.0"' "$FILE"
  deploy_record demo
  [ "$(deployed_events)" = "2" ]
}

@test "an offboarded client is never deployed" {
  yq -i '.status = "offboarded"' "$FILE"
  run "$OPSKIT" deploy demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"offboarded; refusing to deploy"* ]]
  [ ! -e "${REG}/clients/demo/rendered" ]
}

@test "public URL check uses the host's HTTPS port" {
  [ "$(stack_frontend_url demo.localhost 18443)" = "https://demo.localhost:18443" ]
  [ "$(stack_frontend_url auto.acme.com 443)" = "https://auto.acme.com" ]
}

@test "remote stack dir lives under the host's opskit root" {
  yq -i '.opskit_root = "/srv/opskit"' "${REG}/hosts/local-practice.yaml"
  [ "$(stack_remote_dir local-practice demo)" = "/srv/opskit/clients/demo" ]
}
