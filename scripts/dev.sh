#!/usr/bin/env bash
# Starts the mock server on port 4317 and waits until it answers. D3 adds building and opening
# the app below. The mock stops when this script exits.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mock_dir="$repo_root/mock"
port="${MOCK_PORT:-4317}"
host="${MOCK_HOST:-127.0.0.1}"

fail() {
  echo "dev.sh: $*" >&2
  exit 1
}

node_major() {
  node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

# Use the repository's Node (.nvmrc) when nvm is installed and the shell's Node is not 22.
if [[ "$(node_major)" != "22" && -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  source "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  nvm use "$(cat "$repo_root/.nvmrc")" >/dev/null 2>&1 || true
  set -u
fi

command -v node >/dev/null 2>&1 || fail "Node is missing. Install Node 22 with nvm: run 'nvm install' in $repo_root."
[[ "$(node_major)" == "22" ]] || fail "Node 22 is required and this shell has $(node --version). Run 'nvm install' and 'nvm use' in $repo_root, then run this script again."
command -v pnpm >/dev/null 2>&1 || fail "pnpm is missing. Run 'corepack enable' once, then run this script again."
command -v curl >/dev/null 2>&1 || fail "curl is missing, and this script uses it to check that the port is free."

if curl -s -o /dev/null --max-time 1 "http://$host:$port/"; then
  fail "something already answers on $host:$port. Stop it, or set MOCK_PORT to use another port."
fi

cd "$mock_dir"
if [[ ! -d node_modules || pnpm-lock.yaml -nt node_modules/.modules.yaml ]]; then
  echo "Installing the mock's dependencies."
  pnpm install --frozen-lockfile
fi

log_file="$(mktemp -t ian-mock.XXXXXX)"
MOCK_PORT="$port" MOCK_HOST="$host" node --import tsx src/main.ts >"$log_file" 2>&1 &
mock_pid=$!

# Show the mock's log when this script fails, so a crash is never deleted unseen.
cleanup() {
  local status=$?
  kill "$mock_pid" 2>/dev/null || true
  if [[ $status -ne 0 && $status -ne 130 && $status -ne 143 ]]; then
    echo "dev.sh: the mock's log follows." >&2
    cat "$log_file" >&2
  fi
  rm -f "$log_file"
}
trap cleanup EXIT

# This run's own "Mock listening" line is the readiness signal. Probing /me would accept another
# server on the port, and could never succeed in the offline scenario.
ready=0
for _ in $(seq 1 50); do
  if grep -q '^Mock listening' "$log_file"; then
    ready=1
    break
  fi
  kill -0 "$mock_pid" 2>/dev/null || fail "the mock stopped while starting. Is port $port already in use? Set MOCK_PORT to use another."
  sleep 0.2
done
[[ "$ready" == "1" ]] || fail "the mock did not report that it was listening within ten seconds."

echo "Mock listening on http://$host:$port/desktop/v1 (scenario ${MOCK_SCENARIO:-normal})."

# D3: build the app and open it against this mock here (spec section 11, scripts/README.md).

wait "$mock_pid"
