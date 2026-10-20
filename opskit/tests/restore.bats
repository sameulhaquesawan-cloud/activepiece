#!/usr/bin/env bats

load helpers/common
load helpers/registry

NAME=20261001T023000Z

setup() {
  make_registry
  new_demo_client demo
  HOSTROOT="$(mktemp -d)"
  yq -i ".opskit_root = \"${HOSTROOT}\"" "${REG}/hosts/local-practice.yaml"
  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho "docker stub: $*" >&2\nexit 1\n' > "${STUB}/docker"
  chmod +x "${STUB}/docker"
  export PATH="${STUB}:${PATH}"
  KEYDIR="$(mktemp -d)"
  age-keygen -o "${KEYDIR}/key" 2>/dev/null
  export OPSKIT_OWNER_AGE_KEY="${KEYDIR}/key"
  local dir="${HOSTROOT}/backups/demo/${NAME}"
  mkdir -p "$dir"
  printf 'dump' > "${dir}/db.dump"
  ENC="$(openssl rand -hex 16)"
  PGPW="$(openssl rand -hex 32)"
  printf 'AP_API_KEY=%s\nAP_POSTGRES_PASSWORD=%s\nAP_JWT_SECRET=%s\nAP_ENCRYPTION_KEY=%s\nAP_EDITION=ce\n' \
    "$(openssl rand -hex 64)" "$PGPW" "$(openssl rand -hex 32)" "$ENC" \
    | age -r "$(age-keygen -y "${KEYDIR}/key")" -o "${dir}/env.age"
  printf '%s\n' "$NAME" > "${HOSTROOT}/backups/demo/latest"
}

teardown() {
  rm -rf "$REG" "$HOSTROOT" "$STUB" "$KEYDIR"
}

@test "restore fails for an unknown backup name" {
  run "$OPSKIT" restore demo --from 20200101T000000Z --target demo-copy
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup"* ]]
  [ ! -e "${REG}/clients/demo-copy" ]
}

@test "restore without an off-server copy fails when the dump is missing on the host" {
  rm "${HOSTROOT}/backups/demo/${NAME}/db.dump"
  run "$OPSKIT" restore demo --target demo-copy
  [ "$status" -eq 1 ]
  [[ "$output" == *"no off-server remote is configured"* ]]
}

@test "restore over the client itself needs --overwrite" {
  run "$OPSKIT" restore demo --target demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs --overwrite --yes"* ]]
}

@test "restore --overwrite needs --yes and the typed client id" {
  run "$OPSKIT" restore demo --target demo --overwrite
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-run with --yes"* ]]
  run bash -c "echo wrong | '$OPSKIT' restore demo --target demo --overwrite --yes"
  [ "$status" -eq 1 ]
  [[ "$output" == *"typed id does not match"* ]]
}

@test "restore refuses an existing target client" {
  new_demo_client other other.localhost
  run "$OPSKIT" restore demo --target other
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "restore without the owner key fails and creates nothing" {
  export OPSKIT_OWNER_AGE_KEY="${KEYDIR}/missing"
  run "$OPSKIT" restore demo --target demo-copy
  [ "$status" -eq 1 ]
  [[ "$output" == *"owner age private key not found"* ]]
  [ ! -e "${REG}/clients/demo-copy" ]
}

@test "restore with a wrong owner key fails and creates nothing" {
  age-keygen -o "${KEYDIR}/wrong" 2>/dev/null
  export OPSKIT_OWNER_AGE_KEY="${KEYDIR}/wrong"
  run "$OPSKIT" restore demo --target demo-copy
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not decrypt"* ]]
  [ ! -e "${REG}/clients/demo-copy" ]
}

@test "restore rejects a decrypted .env without valid secrets" {
  printf 'AP_EDITION=ce\n' | age -r "$(age-keygen -y "${KEYDIR}/key")" -o "${HOSTROOT}/backups/demo/${NAME}/env.age"
  run "$OPSKIT" restore demo --target demo-copy
  [ "$status" -eq 1 ]
  [[ "$output" == *"lacks valid AP_* secrets"* ]]
  [ ! -e "${REG}/clients/demo-copy" ]
}

@test "restore needs --domain on a host with public TLS" {
  yq -i '.edge.tls = "acme"' "${REG}/hosts/local-practice.yaml"
  run "$OPSKIT" restore demo --target demo-copy
  [ "$status" -eq 1 ]
  [[ "$output" == *"--domain is required"* ]]
}

@test "restore copy keeps the original secrets and creates a draft client" {
  run "$OPSKIT" restore demo --target demo-copy
  [ "$status" -eq 1 ]
  [[ "$output" == *"secrets restored from escrow"* ]]
  [[ "$output" == *"could not start postgres/redis"* ]]
  local secrets="${REG}/clients/demo-copy/secrets.env"
  [ "$(stat -c %a "$secrets")" = "600" ]
  grep -qx "AP_ENCRYPTION_KEY=${ENC}" "$secrets"
  grep -qx "AP_POSTGRES_PASSWORD=${PGPW}" "$secrets"
  ! grep -q AP_EDITION "$secrets"
  local file="${REG}/clients/demo-copy/client.yaml"
  [ "$(yq '.client_id' "$file")" = "demo-copy" ]
  [ "$(yq '.domain' "$file")" = "demo-copy.localhost" ]
  [ "$(yq '.status' "$file")" = "draft" ]
  [ "$(yq '.history[0].event' "$file")" = "restored" ]
  [ "$(yq '.history | length' "$file")" = "1" ]
  [ "$(yq '.offboard_retention_days' "$file")" = "1" ]
}

@test "restore --host refuses an unknown host" {
  run "$OPSKIT" restore demo --target demo-copy --host nowhere
  [ "$status" -eq 1 ]
  [[ "$output" == *"nowhere"* ]]
  [ ! -e "${REG}/clients/demo-copy" ]
}

@test "restore --host copies the backup to the other host and records it there" {
  OTHER="$(mktemp -d)"
  yq ".host_id = \"other\" | .opskit_root = \"${OTHER}\"" "${REG}/hosts/local-practice.yaml" > "${REG}/hosts/other.yaml"
  run "$OPSKIT" restore demo --target demo-copy --host other
  [[ "$output" == *"copied backup ${NAME} from local-practice to other"* ]]
  [ -s "${OTHER}/backups/demo/${NAME}/db.dump" ]
  [ "$(yq '.host.name' "${REG}/clients/demo-copy/client.yaml")" = "other" ]
  [ "$(yq '.host.name' "${REG}/clients/demo/client.yaml")" = "local-practice" ]
  rm -rf "$OTHER"
}

@test "restore fetches the backup from the off-server remote when the host lacks it" {
  local remote
  remote="$(mktemp -d)"
  mkdir -p "${remote}/demo"
  mv "${HOSTROOT}/backups/demo/${NAME}" "${remote}/demo/"
  rm "${HOSTROOT}/backups/demo/latest"
  mkdir -p "${HOSTROOT}/agent"
  printf '[offsite]\ntype = local\n' > "${HOSTROOT}/agent/rclone.conf"
  yq -i ".backup.remote = \"offsite:${remote}\"" "${REG}/clients/demo/client.yaml"
  run "$OPSKIT" restore demo --target demo-copy
  [[ "$output" == *"fetched ${NAME} from off-server"* ]]
  [[ "$output" == *"secrets restored from escrow"* ]]
  [ -s "${HOSTROOT}/backups/demo/${NAME}/db.dump" ]
  rm -rf "$remote"
}

@test "disaster restore moves the client to a new host using the off-server copy" {
  local remote
  remote="$(mktemp -d)"
  OTHER="$(mktemp -d)"
  mkdir -p "${remote}/demo" "${REG}/owner"
  mv "${HOSTROOT}/backups/demo/${NAME}" "${remote}/demo/"
  rm "${HOSTROOT}/backups/demo/latest"
  printf '[offsite]\ntype = local\n' > "${REG}/owner/rclone.conf"
  yq -i ".backup.remote = \"offsite:${remote}\"" "${REG}/clients/demo/client.yaml"
  yq ".host_id = \"other\" | .opskit_root = \"${OTHER}\"" "${REG}/hosts/local-practice.yaml" > "${REG}/hosts/other.yaml"
  run bash -c "echo demo | '$OPSKIT' restore demo --target demo --host other --overwrite --yes"
  [[ "$output" == *"fetched ${NAME} from off-server"*"to other"* ]]
  [[ "$output" == *"demo now lives on other"* ]]
  [ -s "${OTHER}/agent/rclone.conf" ]
  [ -s "${OTHER}/backups/demo/${NAME}/db.dump" ]
  [ "$(yq '.host.name' "${REG}/clients/demo/client.yaml")" = "other" ]
  rm -rf "$remote" "$OTHER"
}
