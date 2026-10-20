make_backup_host() {
  ROOT="$(mktemp -d)"
  STUB="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme"
  cp "${OPSKIT_ROOT}/agent/backup.sh" "${OPSKIT_ROOT}/agent/alert.sh" "${ROOT}/agent/"
  echo "age1testpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" > "${ROOT}/agent/owner.age.pub"
  printf 'AP_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef\n' > "${ROOT}/clients/acme/.env"
  echo "name: acme" > "${ROOT}/clients/acme/compose.yml"
  cat > "${STUB}/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  ps) [ "${FAKE_PG_DOWN:-}" = "1" ] || echo cid ;;
  exec)
    if [ "$2" = "-i" ]; then cat >/dev/null; exit 0; fi
    printf 'PGDMP-fake-dump'
    ;;
esac
SH
  cat > "${STUB}/age" <<'SH'
#!/usr/bin/env bash
out=""; in=""
while [ "$#" -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -R) shift 2 ;; *) in="$1"; shift ;; esac; done
printf 'age-encrypted:%s' "$(wc -c < "$in")" > "$out"
SH
  chmod +x "${STUB}/docker" "${STUB}/age"
  export PATH="${STUB}:${PATH}"
  AGENT="${ROOT}/agent/backup.sh"
}
