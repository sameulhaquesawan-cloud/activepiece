make_registry() {
  REG="$(mktemp -d)"
  mkdir -p "${REG}/hosts" "${REG}/clients"
  cp "${OPSKIT_ROOT}/tests/fixtures/hosts/local-practice.yaml" "${REG}/hosts/"
  export OPSKIT_REGISTRY="$REG"
}

new_demo_client() {
  "$OPSKIT" client new "${1:-demo}" --domain "${2:-demo.localhost}" --host local-practice --contact ops@example.com >/dev/null
}
