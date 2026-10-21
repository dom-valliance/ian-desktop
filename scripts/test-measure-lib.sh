#!/usr/bin/env bash
# Checks the parsing in measure-lib.sh against fixed samples. Needs no display and starts nothing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=measure-lib.sh
source "$here/measure-lib.sh"

failures=0
expect() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL $name: wanted '$want', got '$got'" >&2
    failures=$((failures + 1))
  fi
}

# What the mock's /__mock/state sends (mock/src/http/app.ts).
state_idle='{"scenario":"normal","now":"2026-10-20T09:30:00.000Z","latestEventId":1792503670142,"openStreams":0,"minClientVersion":"0.1.0"}'
state_live='{"scenario":"normal","now":"2026-10-20T09:30:00.000Z","latestEventId":1792503670142,"openStreams":2,"minClientVersion":"0.1.0"}'

expect "no streams" "0" "$(open_streams_from_json <<<"$state_idle")"
expect "two streams" "2" "$(open_streams_from_json <<<"$state_live")"
expect "empty reply fails" "failed" "$(open_streams_from_json <<<"" >/dev/null && echo ok || echo failed)"
expect "reply without the field fails" "failed" \
  "$(open_streams_from_json <<<'{"scenario":"normal"}' >/dev/null && echo ok || echo failed)"

expect "seconds only" "7.25" "$(echo "0:07.25" | cpu_seconds_from_ps)"
expect "minutes" "125.5" "$(echo "2:05.50" | cpu_seconds_from_ps)"
expect "hours" "3725" "$(echo "1:02:05.00" | cpu_seconds_from_ps)"

expect "average and peak" "20.0 30.0" "$(printf '10.0\n20.0\n30.0\n' | summarise_rss)"
expect "no samples fail" "failed" "$(printf '' | summarise_rss >/dev/null && echo ok || echo failed)"

if ((failures > 0)); then
  echo "$failures check(s) failed." >&2
  exit 1
fi
echo "measure-lib: all checks passed."
