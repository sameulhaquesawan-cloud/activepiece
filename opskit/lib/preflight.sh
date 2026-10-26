#!/usr/bin/env bash
# Read-only checks of a host before bootstrap/deploy (task 9.4) and the cloud-init user-data for a new
# server. Needs registry.sh, host.sh, deploy.sh (preflight_dns).

# host_preflight <host>: one line per check; non-zero when any check fails. Changes nothing.
host_preflight() {
  local host="$1" file failed=0 out value want
  file="$(host_file "$host")"
  if ! host_run "$host" true >/dev/null 2>&1; then
    log_fail "ssh: cannot run commands on ${host} as $(yaml_get "$file" .ssh_user)"
    return 1
  fi
  log_ok "ssh: commands run on ${host}"
  if [ "$(host_transport "$host")" != "local" ]; then
    if host_run "$host" sudo -n true >/dev/null 2>&1; then log_ok "sudo: works without a password"
    else log_fail "sudo: needs a password (give $(yaml_get "$file" .ssh_user) passwordless sudo)"; failed=1; fi
  fi
  # shellcheck disable=SC2016 # expanded by the remote shell
  value="$(host_run "$host" sh -c '. /etc/os-release && printf "%s %s" "$ID" "$VERSION_ID"' 2>/dev/null || true)"
  if [ "$value" = "ubuntu 24.04" ]; then log_ok "OS: Ubuntu 24.04"
  else log_fail "OS: ${value:-unknown} (bootstrap needs Ubuntu 24.04)"; failed=1; fi
  log_ok "CPU: $(host_run "$host" uname -m 2>/dev/null || printf '?'), $(host_run "$host" nproc 2>/dev/null || printf '?') core(s)"
  value="$(host_run "$host" sh -c "awk '/^MemTotal:/ {print int(\$2/1048576+0.5)}' /proc/meminfo" 2>/dev/null || printf 0)"
  want="$(yaml_get "$file" .ram_gb 4)"
  if [ "${value:-0}" -ge "$want" ]; then log_ok "memory: ${value} GB (host yaml says ${want})"
  else log_warn "memory: ${value} GB, host yaml says ${want}"; fi
  value="$(host_run "$host" sh -c "df -Pk / | awk 'NR==2 {print int(\$4/1048576)}'" 2>/dev/null || printf 0)"
  if [ "${value:-0}" -ge 10 ]; then log_ok "disk: ${value} GB free on /"
  else log_fail "disk: only ${value} GB free on / (need 10+)"; failed=1; fi
  value="$(host_run "$host" cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || printf 0)"
  if [ "$value" = "1" ]; then log_fail "IPv6 is disabled in the kernel (the Activepieces app needs it to listen)"; failed=1
  else log_ok "IPv6: enabled in the kernel"; fi
  if host_run "$host" sh -c 'command -v crontab' >/dev/null 2>&1; then log_ok "cron: installed"
  else log_warn "cron: missing (bootstrap installs it)"; fi
  if out="$(host_run "$host" docker --version 2>/dev/null)"; then log_ok "docker: ${out} (kept by bootstrap)"
  else log_ok "docker: not installed (bootstrap installs it)"; fi
  for value in https://cloud.activepieces.com https://ghcr.io https://registry.npmjs.org; do
    if host_run "$host" curl -sS -o /dev/null -m 10 "$value" >/dev/null 2>&1; then log_ok "outbound HTTPS: ${value}"
    else log_fail "outbound HTTPS: ${value} not reachable from ${host}"; failed=1; fi
  done
  if preflight_needs_dns "$host"; then
    local domain
    for domain in $(yq -r '.monitor.domain // ""' "$file") $(preflight_host_domains "$host"); do
      [ -n "$domain" ] || continue
      preflight_dns "$domain" "$(yaml_get "$file" .ip)" || failed=1
    done
  fi
  if [ "$failed" -eq 0 ]; then
    log_ok "preflight of ${host} passed"
  else
    log_fail "preflight of ${host}: fix the [fail] lines above"
  fi
  return "$failed"
}

# preflight_host_domains <host>: domains of the clients registered on the host (offboarded ones excluded)
preflight_host_domains() {
  local file
  for file in "$(registry_root)"/clients/*/client.yaml; do
    [ -f "$file" ] || continue
    [ "$(yaml_get "$file" .host.name)" = "$1" ] || continue
    [ "$(yaml_get "$file" .status)" != "offboarded" ] || continue
    yaml_get "$file" .domain
  done
}

# host_cloud_init <user> <public key file>: #cloud-config for the provider's "user data" box
host_cloud_init() {
  local user="$1" keyfile="$2" key
  if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || [ "$user" = "root" ]; then
    log_fail "--user must be a non-root Linux user name"
    return 1
  fi
  [ -f "$keyfile" ] || { log_fail "public key file not found: ${keyfile}"; return 1; }
  key="$(head -n 1 "$keyfile")"
  if [[ ! "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\ [A-Za-z0-9+/=]+(\ .*)?$ ]]; then
    log_fail "${keyfile} is not an SSH public key (use the .pub file, never the private key)"
    return 1
  fi
  printf '#cloud-config\nusers:\n  - name: %s\n    groups: [sudo]\n    shell: /bin/bash\n    sudo: "ALL=(ALL) NOPASSWD:ALL"\n    lock_passwd: true\n    ssh_authorized_keys:\n      - "%s"\ndisable_root: true\nssh_pwauth: false\n' \
    "$user" "$key"
}
