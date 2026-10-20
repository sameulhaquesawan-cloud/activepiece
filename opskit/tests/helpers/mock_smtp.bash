start_mock_smtp() {
  SMTP_DIR="$(mktemp -d)"
  python3 -I "${OPSKIT_ROOT}/tests/helpers/mock_smtp.py" "${SMTP_DIR}/mails.jsonl" "${SMTP_DIR}/port" &
  SMTP_PID=$!
  local _
  for _ in $(seq 1 50); do
    [ -s "${SMTP_DIR}/port" ] && break
    sleep 0.1
  done
  SMTP_URL="smtp://127.0.0.1:$(cat "${SMTP_DIR}/port")"
  touch "${SMTP_DIR}/mails.jsonl"
}

stop_mock_smtp() {
  [ -z "${SMTP_PID:-}" ] || kill "$SMTP_PID" 2>/dev/null || true
  rm -rf "${SMTP_DIR:-}"
}

mock_mails() {
  cat "${SMTP_DIR}/mails.jsonl"
}
