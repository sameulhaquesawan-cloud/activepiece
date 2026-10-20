#!/usr/bin/env bash
# Logging helpers: one-line step summaries ([ok] / [warn] / [fail]) on stderr-safe stdout.

log_ok() {
  printf '[ok] %s\n' "$*"
}

log_warn() {
  printf '[warn] %s\n' "$*"
}

log_fail() {
  printf '[fail] %s\n' "$*" >&2
}

log_info() {
  printf '%s\n' "$*"
}

die() {
  log_fail "$*"
  exit 1
}
