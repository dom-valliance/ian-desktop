#!/usr/bin/env bash
# Writes the scenario fixtures: the `today`, `views` and `items` of the mock's `quiet`, `normal`,
# `overloaded` and `incident` snapshots, and `me`, taken at a fixed mock time, to
# Packages/IanKit/Tests/TestSupport/Fixtures/<scenario>.json. The Orbit, Pillars and view tests
# all read that one copy. Starts the mock on a free port and stops it on exit. Running it twice
# gives byte-identical files.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mock_dir="$repo_root/mock"
out_dir="$repo_root/Packages/IanKit/Tests/TestSupport/Fixtures"
host="127.0.0.1"
fixed_time="2026-10-16T09:30:00.000Z"
scenarios=(quiet normal overloaded incident)

fail() {
  echo "export-scenario-fixtures.sh: $*" >&2
  exit 1
}

node_major() {
  node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

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
command -v curl >/dev/null 2>&1 || fail "curl is missing, and this script uses it to talk to the mock."

cd "$mock_dir"
if [[ ! -d node_modules || pnpm-lock.yaml -nt node_modules/.modules.yaml ]]; then
  pnpm install --frozen-lockfile
fi

port="$(node -e "const s=require('net').createServer();s.listen(0,'$host',()=>{console.log(s.address().port);s.close()})")"
base="http://$host:$port"
log_file="$(mktemp -t ian-fixtures-mock.XXXXXX)"

MOCK_PORT="$port" MOCK_HOST="$host" node --import tsx src/main.ts >"$log_file" 2>&1 &
mock_pid=$!

cleanup() {
  kill "$mock_pid" 2>/dev/null || true
  wait "$mock_pid" 2>/dev/null || true
  rm -f "$log_file"
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 50); do
  if grep -q '^Mock listening' "$log_file"; then
    ready=1
    break
  fi
  kill -0 "$mock_pid" 2>/dev/null || fail "the mock stopped while starting. Its log follows: $(cat "$log_file")"
  sleep 0.2
done
[[ "$ready" == "1" ]] || fail "the mock did not report that it was listening within ten seconds."

mkdir -p "$out_dir"
for scenario in "${scenarios[@]}"; do
  curl -fsS -X POST "$base/__mock/scenario" -H 'content-type: application/json' \
    -d "{\"scenario\":\"$scenario\"}" >/dev/null || fail "the mock refused the scenario '$scenario'."
  curl -fsS -X POST "$base/__mock/clock" -H 'content-type: application/json' \
    -d "{\"set\":\"$fixed_time\"}" >/dev/null || fail "the mock refused the clock setting."
  snapshot_file="$(mktemp -t ian-fixtures-snapshot.XXXXXX)"
  me_file="$(mktemp -t ian-fixtures-me.XXXXXX)"
  curl -fsS "$base/desktop/v1/snapshot" -H 'Authorization: Bearer dev-fixtures' >"$snapshot_file" ||
    fail "could not read the '$scenario' snapshot."
  curl -fsS "$base/desktop/v1/me" -H 'Authorization: Bearer dev-fixtures' >"$me_file" ||
    fail "could not read the '$scenario' principal."
  node -e '
    const fs = require("fs");
    const snapshot = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const me = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    const fixture = { today: snapshot.today, views: snapshot.views, items: snapshot.items, me };
    process.stdout.write(JSON.stringify(fixture, null, 2) + "\n");
  ' "$snapshot_file" "$me_file" >"$out_dir/$scenario.json" || fail "could not write the '$scenario' fixture."
  echo "Wrote $out_dir/$scenario.json"
  rm -f "$snapshot_file" "$me_file"
done
