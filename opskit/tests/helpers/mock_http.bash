start_mock_http() {
  MOCK_DIR="$(mktemp -d)"
  python3 -I "${OPSKIT_ROOT}/tests/helpers/mock_http.py" "${MOCK_DIR}/requests.jsonl" "${MOCK_DIR}/port" "${MOCK_RESPONSES:-}" &
  MOCK_PID=$!
  local _
  for _ in $(seq 1 50); do
    [ -s "${MOCK_DIR}/port" ] && break
    sleep 0.1
  done
  MOCK_URL="http://127.0.0.1:$(cat "${MOCK_DIR}/port")"
  touch "${MOCK_DIR}/requests.jsonl"
}

stop_mock_http() {
  [ -z "${MOCK_PID:-}" ] || kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "${MOCK_DIR:-}"
}

mock_requests() {
  cat "${MOCK_DIR}/requests.jsonl"
}
