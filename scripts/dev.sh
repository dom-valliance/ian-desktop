#!/usr/bin/env bash
# Starts the mock server on port 4317, waits until it answers, then builds the app and opens it
# against the mock. `--mock-only` starts only the mock. The mock stops when this script exits.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mock_dir="$repo_root/mock"
port="${MOCK_PORT:-4317}"
host="${MOCK_HOST:-127.0.0.1}"

fail() {
  echo "dev.sh: $*" >&2
  exit 1
}

mock_only=0
case "${1:-}" in
  "") ;;
  --mock-only) mock_only=1 ;;
  *) fail "unknown option '$1'. Run with no option, or with --mock-only to start only the mock." ;;
esac

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

# Show the mock's log when the mock itself has died, so a crash is never deleted unseen.
cleanup() {
  local status=$?
  local mock_died=0
  kill -0 "$mock_pid" 2>/dev/null || mock_died=1
  kill "$mock_pid" 2>/dev/null || true
  if [[ $mock_died -eq 1 && $status -ne 0 && $status -ne 130 && $status -ne 143 ]]; then
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

if [[ $mock_only -eq 1 ]]; then
  echo "Mock only. Press Ctrl-C to stop it."
elif [[ "$port" != "4317" ]]; then
  echo "The app's mock profile expects port 4317, so it is not opened against port $port."
else
  xcodebuild -version >/dev/null 2>&1 ||
    fail "Xcode 27 is needed to build the app (ADR 0010). Install it, run 'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer', then run this script again."
  derived_data="$repo_root/build/DerivedData"
  build_log="$(mktemp -t ian-build.XXXXXX)"
  echo "Building the app. The first build takes a few minutes."
  if ! xcodebuild -project "$repo_root/App/Ian.xcodeproj" -scheme Ian -configuration Debug \
    -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
    -derivedDataPath "$derived_data" build >"$build_log" 2>&1; then
    tail -n 30 "$build_log" >&2
    rm -f "$build_log"
    fail "the app did not build. The last lines of its build log are above."
  fi
  rm -f "$build_log"
  open "$derived_data/Build/Products/Debug/Ian.app"
  echo "Ian is open: the word \"Ian\" at the right of the menu bar, on every display. On a laptop"
  echo "with a full menu bar it can sit hidden behind the camera notch. Press Ctrl-C to stop the mock."
fi

wait "$mock_pid"
