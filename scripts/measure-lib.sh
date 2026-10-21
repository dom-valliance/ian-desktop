#!/usr/bin/env bash
# The parsing `measure-cpu.sh` does on what `ps` and the mock print, kept apart so
# `test-measure-lib.sh` can run it on fixtures without a display, a build or the app.

# Reads the mock's `GET /__mock/state` body and prints its `openStreams` number. Prints nothing
# and fails when the body has none, such as an empty reply from a mock that is not up yet.
open_streams_from_json() {
  local body count
  body="$(cat)"
  count="$(sed -nE 's/.*"openStreams":([0-9]+).*/\1/p' <<<"$body")"
  [[ -n "$count" ]] || return 1
  printf '%s\n' "$count"
}

# Reads ps's [[hh:]mm:]ss.cc form and prints seconds.
cpu_seconds_from_ps() {
  awk '{ n = split($1, p, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + p[i]; print s }'
}

# Reads megabyte samples, one per line, and prints their average and their peak.
summarise_rss() {
  awk '{ s += $1; if ($1 > m) m = $1; n++ } END { if (n == 0) exit 1; printf "%.1f %.1f\n", s / n, m }'
}
