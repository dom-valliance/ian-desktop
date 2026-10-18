#!/usr/bin/env bash
# Starts the mock server on port 4317 and waits until it answers. D3 adds building and opening
# the app below. The mock stops when this script exits.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mock_dir="$repo_root/mock"
port="${MOCK_PORT:-4317}"
host="${MOCK_HOST:-127.0.0.1}"
base_url="http://$host:$port/desktop/v1"

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
  (cd "$repo_root" && nvm use >/dev/null) || true
  nvm use 22 >/dev/null 2>&1 || true
  set -u
fi

command -v node >/dev/null 2>&1 || fail "Node is missing. Install Node 22 with nvm: run 'nvm install' in $repo_root."
[[ "$(node_major)" == "22" ]] || fail "Node 22 is required and this shell has $(node --version). Run 'nvm install' and 'nvm use' in $repo_root, then run this script again."
command -v pnpm >/dev/null 2>&1 || fail "pnpm is missing. Run 'corepack enable' once, then run this script again."
command -v curl >/dev/null 2>&1 || fail "curl is missing, and this script uses it to check the mock."

cd "$mock_dir"
if [[ ! -d node_modules || pnpm-lock.yaml -nt node_modules/.modules.yaml ]]; then
  echo "Installing the mock's dependencies."
  pnpm install --frozen-lockfile
fi

log_file="$(mktemp -t ian-mock.XXXXXX)"
MOCK_PORT="$port" MOCK_HOST="$host" node --import tsx src/main.ts >"$log_file" 2>&1 &
mock_pid=$!

cleanup() {
  kill "$mock_pid" 2>/dev/null || true
  rm -f "$log_file"
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 50); do
  if ! kill -0 "$mock_pid" 2>/dev/null; then
    cat "$log_file" >&2
    fail "the mock stopped while starting. Is port $port already in use? Set MOCK_PORT to use another."
  fi
  if curl -fsS -o /dev/null -H 'Authorization: Bearer dev-local' "$base_url/me" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 0.2
done
[[ "$ready" == "1" ]] || { cat "$log_file" >&2; fail "the mock did not answer on $base_url within ten seconds."; }

echo "Mock listening on $base_url (scenario ${MOCK_SCENARIO:-normal})."

# D3: build the app and open it against this mock here (spec section 11, scripts/README.md).

wait "$mock_pid"
