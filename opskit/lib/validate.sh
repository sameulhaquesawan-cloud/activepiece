#!/usr/bin/env bash
# Small value validators. Each returns 0 when valid, 1 otherwise, and prints nothing.

is_slug() {
  [[ "$1" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ ]] && [[ "$1" != *--* ]]
}

is_domain() {
  local value="$1"
  [ "${#value}" -le 253 ] || return 1
  [[ "$value" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]
}

is_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]{0,8}$ ]]
}

is_port() {
  is_positive_int "$1" && [ "$1" -le 65535 ]
}
