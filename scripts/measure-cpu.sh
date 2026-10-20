#!/usr/bin/env bash
# Measures Ian's own process in a Release build against the mock (P1 and D9, spec 6.9 and 11):
# the Orbit alone in `quiet`, `normal` and `incident`, and the expanded client open on Today in
# `normal`. CPU is the change in the process's cumulative CPU time over 30 seconds, after a
# 10-second warm-up. Resident memory is the average and the peak of `ps -o rss`, sampled each
# second over the same 30 seconds. Launch to data is the time from starting the process to the
# mock reporting an open event stream, for each launch. Prints three tables and exits non-zero when
# a target is missed.
#
# Memory: under 150 MB resident for the Orbit-only states (spec 6.9). The panel's figure has no
# target and is shown for the record.
#
# Launch to data: spec 11 wants the `normal` scenario on screen within ten seconds of launch,
# for an unsigned Debug build run through `dev.sh`. The app logs nothing when it applies the first
# snapshot, so this reads the nearest outside signal: the sync engine applies the snapshot and
# only then opens the event stream, and the mock's `GET /__mock/state` reports `openStreams`. The
# time is from starting the process to the first poll that sees an open stream, polled every
# 50 ms. It is a tight proxy for the first snapshot applied, not the moment SwiftUI draws it.
# The first request the app makes is `GET /me`, long before the snapshot, so a connection to the
# mock proves nothing. Before each launch the script waits until the mock reports no stream, so
# a stream left by the last launch is never counted. The Release figures come from the two
# Release launches, the first with a cold start. The Debug figure is one launch of the Debug
# build, built as `dev.sh` builds it, into `build/DerivedData`, and is the one spec 11 names.
#
# No M1 is available, so each target is two thirds of the spec's budget on this machine:
# the Orbit alone under 0.7% in `normal` and `incident`, the panel open under 10%.
#
# The table also shows WindowServer's CPU over the same windows, with no target: Core Animation
# moves the Orbit's per-frame work out of Ian's process, and this keeps its cost on record. It
# includes everything else on screen, so read it as context.
#
# The Orbit-only `normal` figure is not checked against `quiet`: both are a few hundredths of a
# CPU second a second, within the noise of `ps`'s 0.01 s resolution, so the check would not be
# reliable. The panel is checked against the Orbit-only `normal` figure, where the gap is large.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=measure-lib.sh
source "$repo_root/scripts/measure-lib.sh"
# The app's mock profile is fixed at port 4317, so the port cannot change.
port=4317
base="http://127.0.0.1:$port"
derived_data="$repo_root/build/DerivedDataRelease"
app_bin="$derived_data/Build/Products/Release/Ian.app/Contents/MacOS/Ian"
debug_derived_data="$repo_root/build/DerivedData"
debug_app_bin="$debug_derived_data/Build/Products/Debug/Ian.app/Contents/MacOS/Ian"
warm_up=10
window=30
orbit_target=0.7
panel_target=10
memory_target_mb=150
launch_target=10

fail() {
  echo "measure-cpu.sh: $*" >&2
  exit 1
}

[[ "$(xcodebuild -version 2>/dev/null | head -n 1)" == "Xcode 27"* ]] ||
  fail "Xcode 27 is needed (ADR 0010). Install it and run 'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'."
for tool in curl lsof perl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is missing, and this script needs it."
done

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
[[ "$(node_major)" == "22" ]] || fail "Node 22 is required. Run 'nvm install' and 'nvm use' in $repo_root, then run this script again."
command -v pnpm >/dev/null 2>&1 || fail "pnpm is missing. Run 'corepack enable' once, then run this script again."

if curl -s -o /dev/null --max-time 1 "$base/"; then
  fail "something already answers on port $port. Stop it, then run this script again."
fi
if pgrep -f "$app_bin" >/dev/null; then
  fail "a Release Ian from this checkout is already running. Quit it, then run this script again."
fi

mock_pid=""
caffeinate_pid=""
mock_children=""
app_pid=""
# Every temporary file lives here, so the one trap removes them all, including those a command
# substitution's subshell made before it failed.
work_dir="$(mktemp -d -t ian-measure.XXXXXX)"
mock_log="$work_dir/mock.log"

is_gone() {
  ! kill -0 "$1" 2>/dev/null
}

stop_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || return 0
  wait_until 5 is_gone "$pid" || kill -9 "$pid" 2>/dev/null || true
}

stop_app() {
  stop_pid "$app_pid"
  app_pid=""
}

# Stops what this script started, by pid, and reports anything that is still running. It runs on
# every exit: success, a failed check, `fail`, and a signal.
cleanup() {
  local status=$?
  trap - EXIT
  stop_app
  local child
  for child in $mock_children; do stop_pid "$child"; done
  stop_pid "$mock_pid"
  stop_pid "$caffeinate_pid"
  rm -rf "$work_dir"
  sleep 0.5
  if pgrep -f "$app_bin" >/dev/null || pgrep -f "$debug_app_bin" >/dev/null; then
    echo "measure-cpu.sh: Ian is still running; stop it by hand." >&2
    status=1
  fi
  for child in $mock_children $mock_pid; do
    if [[ -n "$child" ]] && kill -0 "$child" 2>/dev/null; then
      echo "measure-cpu.sh: process $child is still running; stop it by hand." >&2
      status=1
    fi
  done
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

now() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# Runs a command every 50 ms until it succeeds or `seconds` of elapsed time pass, however long
# each run took. Returns non-zero on the deadline.
wait_until() {
  local seconds="$1"
  shift
  local started
  started="$(now)"
  while true; do
    "$@" && return 0
    awk -v a="$started" -v b="$(now)" -v limit="$seconds" 'BEGIN { exit !(b - a < limit) }' ||
      return 1
    sleep 0.05
  done
}

# A sleeping display, a screen lock or a screen saver would occlude the Orbit and the panel, which
# stops their animation and makes the figures meaninglessly low. `-w` ends it with this script.
caffeinate -d -i -w $$ &
caffeinate_pid=$!
disown "$caffeinate_pid"

echo "Building Ian in Release. The first build takes a few minutes."
build_log="$work_dir/build.log"
if ! xcodebuild -project "$repo_root/App/Ian.xcodeproj" -scheme Ian -configuration Release \
  -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath "$derived_data" build >"$build_log" 2>&1; then
  tail -n 30 "$build_log" >&2
  fail "the Release build failed. The last lines of its log are above."
fi
[[ -x "$app_bin" ]] || fail "the build did not produce $app_bin."

# The Debug build spec 11's ten seconds is about, built as dev.sh builds it.
echo "Building Ian in Debug, as dev.sh does."
if ! xcodebuild -project "$repo_root/App/Ian.xcodeproj" -scheme Ian -configuration Debug \
  -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath "$debug_derived_data" build >"$build_log" 2>&1; then
  tail -n 30 "$build_log" >&2
  fail "the Debug build failed. The last lines of its log are above."
fi
[[ -x "$debug_app_bin" ]] || fail "the build did not produce $debug_app_bin."

MOCK_PORT="$port" "$repo_root/scripts/dev.sh" --mock-only >"$mock_log" 2>&1 &
mock_pid=$!
# Disowned, so bash does not print a "Terminated" notice when the cleanup stops it.
disown "$mock_pid"
mock_listening() {
  grep -q '^Mock listening' "$mock_log" || {
    kill -0 "$mock_pid" 2>/dev/null || {
      cat "$mock_log" >&2
      fail "the mock stopped while starting."
    }
    return 1
  }
}
wait_until 20 mock_listening || fail "the mock did not report that it was listening within twenty seconds."
wait_until 5 curl -s -o /dev/null --max-time 1 "$base/__mock/sessions" ||
  fail "the mock did not answer on $base within five seconds."
mock_children="$(pgrep -P "$mock_pid" || true)"

set_scenario() {
  curl -sf -o /dev/null -X POST -H 'content-type: application/json' \
    -d "{\"scenario\":\"$1\"}" "$base/__mock/scenario" ||
    fail "the mock did not accept the scenario '$1'."
}

# How many event streams the mock holds open. Fails while the mock does not answer.
open_streams() {
  curl -s --max-time 1 "$base/__mock/state" | open_streams_from_json
}

streams_closed() {
  [[ "$(open_streams 2>/dev/null || echo unknown)" == "0" ]]
}

stream_open() {
  kill -0 "$app_pid" 2>/dev/null || fail "Ian exited while starting."
  local count
  count="$(open_streams 2>/dev/null || echo 0)"
  ((count >= 1))
}

# Starts the binary on the mock, with any extra launch arguments, and waits until the mock reports
# an open event stream, which the app opens only after it has applied the first snapshot. It
# first waits until the mock holds no stream, so one left by an earlier launch is not counted.
launch_app() {
  local binary="$1"
  shift
  wait_until 10 streams_closed || fail "the mock still held an event stream before the launch."
  launch_started="$(now)"
  "$binary" -IanEnvironment mock "$@" >/dev/null 2>&1 &
  app_pid=$!
  disown "$app_pid"
  # The child shows the shell's command line until it has executed, so give it a second.
  local command=""
  for _ in $(seq 1 10); do
    command="$(ps -o command= -p "$app_pid" 2>/dev/null || true)"
    [[ "$command" == "$binary"* ]] && break
    sleep 0.1
  done
  [[ "$command" == "$binary"* ]] ||
    fail "pid $app_pid is not Ian's binary (its command is '$command')."
  wait_until 20 stream_open || fail "the mock reported no event stream within twenty seconds."
  launch_seconds="$(awk -v t0="$launch_started" -v t1="$(now)" 'BEGIN { printf "%.2f", t1 - t0 }')"
}

# Stops the app and waits until the mock has dropped its stream.
stop_app_and_wait() {
  stop_app
  wait_until 10 streams_closed || fail "the mock still held an event stream after Ian stopped."
}

# Cumulative CPU time of the process in seconds.
cpu_seconds() {
  ps -o time= -p "$1" | cpu_seconds_from_ps
}

# Resident set size of a process in megabytes, from ps's kilobytes.
rss_mb() {
  ps -o rss= -p "$1" | awk '{ printf "%.1f\n", $1 / 1024 }'
}

# Prints Ian's CPU percentage, WindowServer's, and Ian's average and peak resident megabytes over
# the measuring window.
measure() {
  sleep "$warm_up"
  kill -0 "$app_pid" 2>/dev/null || fail "Ian exited during the warm-up."
  local cpu_before time_before cpu_after time_after ws_before ws_after samples rss
  cpu_before="$(cpu_seconds "$app_pid")"
  ws_before="$(cpu_seconds "$window_server_pid")"
  time_before="$(now)"
  samples="$work_dir/rss.$$.$RANDOM"
  for _ in $(seq 1 "$window"); do
    sleep 1
    kill -0 "$app_pid" 2>/dev/null || fail "Ian exited during the measurement."
    rss_mb "$app_pid" >>"$samples"
  done
  cpu_after="$(cpu_seconds "$app_pid")"
  ws_after="$(cpu_seconds "$window_server_pid")"
  time_after="$(now)"
  rss="$(summarise_rss <"$samples")" || fail "no resident memory samples were taken."
  awk -v c0="$cpu_before" -v c1="$cpu_after" -v w0="$ws_before" -v w1="$ws_after" \
    -v t0="$time_before" -v t1="$time_after" -v rss="$rss" \
    'BEGIN { printf "%.2f %.2f %s\n", (c1 - c0) / (t1 - t0) * 100, (w1 - w0) / (t1 - t0) * 100, rss }'
}

window_server_pid="$(pgrep -x WindowServer | head -n 1 || true)"
[[ -n "$window_server_pid" ]] || fail "WindowServer is not running, so there is no display to measure."

echo "Measuring the Orbit alone."
launch_app "$app_bin"
orbit_launch="$launch_seconds"
set_scenario quiet
result="$(measure)"
read -r quiet quiet_ws quiet_rss quiet_peak <<<"$result"
set_scenario normal
result="$(measure)"
read -r normal normal_ws normal_rss normal_peak <<<"$result"
set_scenario incident
result="$(measure)"
read -r incident incident_ws incident_rss incident_peak <<<"$result"
stop_app_and_wait

echo "Measuring the panel open on Today."
set_scenario normal
launch_app "$app_bin" -IanOpenPanelOnLaunch YES
panel_launch="$launch_seconds"
result="$(measure)"
read -r panel panel_ws panel_rss panel_peak <<<"$result"
stop_app_and_wait

echo "Timing launch to data on the Debug build."
set_scenario normal
launch_app "$debug_app_bin"
debug_launch="$launch_seconds"
stop_app_and_wait

status=0
verdict() {
  if awk -v v="$1" -v t="$2" 'BEGIN { exit !(v < t) }'; then
    echo "met"
  else
    echo "MISSED"
  fi
}

normal_verdict="$(verdict "$normal" "$orbit_target")"
incident_verdict="$(verdict "$incident" "$orbit_target")"
panel_verdict="$(verdict "$panel" "$panel_target")"
# The field costs several points of CPU, so a panel that is not clearly above the Orbit alone did
# not open, or was not on screen.
opened="yes"
if ! awk -v p="$panel" -v n="$normal" 'BEGIN { exit !(p > n + 2) }'; then
  opened="NO"
  status=1
fi

# A memory target is met when the peak, not the average, stays under it.
memory_verdict() {
  if awk -v v="$1" -v t="$memory_target_mb" 'BEGIN { exit !(v < t) }'; then echo "met"; else echo "MISSED"; fi
}
quiet_mem_verdict="$(memory_verdict "$quiet_peak")"
normal_mem_verdict="$(memory_verdict "$normal_peak")"
incident_mem_verdict="$(memory_verdict "$incident_peak")"
orbit_launch_verdict="$(verdict "$orbit_launch" "$launch_target")"
debug_launch_verdict="$(verdict "$debug_launch" "$launch_target")"
panel_launch_verdict="$(verdict "$panel_launch" "$launch_target")"
for result in "$normal_verdict" "$incident_verdict" "$panel_verdict" "$quiet_mem_verdict" \
  "$normal_mem_verdict" "$incident_mem_verdict" "$orbit_launch_verdict" "$panel_launch_verdict" \
  "$debug_launch_verdict"; do
  [[ "$result" == "MISSED" ]] && status=1
done

echo
echo "Machine: $(sysctl -n machdep.cpu.brand_string) ($(sysctl -n hw.model)), $(sw_vers -productName) $(sw_vers -productVersion)"
echo "CPU and memory: Release build, mock scenarios, ${window} s after a ${warm_up} s warm-up."
printf '%-30s %8s %10s %8s %14s\n' "State" "Ian CPU %" "Target" "Result" "WindowServer %"
printf '%-30s %8s %10s %8s %14s\n' "Orbit only, quiet" "$quiet" "none" "-" "$quiet_ws"
printf '%-30s %8s %10s %8s %14s\n' "Orbit only, normal" "$normal" "< $orbit_target" "$normal_verdict" "$normal_ws"
printf '%-30s %8s %10s %8s %14s\n' "Orbit only, incident" "$incident" "< $orbit_target" "$incident_verdict" "$incident_ws"
printf '%-30s %8s %10s %8s %14s\n' "Panel open on Today, normal" "$panel" "< $panel_target" "$panel_verdict" "$panel_ws"

echo
echo "Resident memory, sampled each second over the same window."
printf '%-30s %10s %8s %10s %8s\n' "State" "Average MB" "Peak MB" "Target" "Result"
printf '%-30s %10s %8s %10s %8s\n' "Orbit only, quiet" "$quiet_rss" "$quiet_peak" "< $memory_target_mb" "$quiet_mem_verdict"
printf '%-30s %10s %8s %10s %8s\n' "Orbit only, normal" "$normal_rss" "$normal_peak" "< $memory_target_mb" "$normal_mem_verdict"
printf '%-30s %10s %8s %10s %8s\n' "Orbit only, incident" "$incident_rss" "$incident_peak" "< $memory_target_mb" "$incident_mem_verdict"
printf '%-30s %10s %8s %10s %8s\n' "Panel open on Today, normal" "$panel_rss" "$panel_peak" "none" "-"

echo
echo "Launch to data: process start to the mock reporting an open event stream, which follows the first snapshot."
printf '%-34s %10s %10s %8s\n' "Launch" "Seconds" "Target" "Result"
printf '%-34s %10s %10s %8s\n' "Release, Orbit only, normal (cold)" "$orbit_launch" "< $launch_target" "$orbit_launch_verdict"
printf '%-34s %10s %10s %8s\n' "Release, panel open, normal" "$panel_launch" "< $launch_target" "$panel_launch_verdict"
printf '%-34s %10s %10s %8s\n' "Debug (dev.sh build), normal" "$debug_launch" "< $launch_target" "$debug_launch_verdict"
echo "The Debug figure is the one spec 11 names: an unsigned Debug build as dev.sh builds it."

if [[ "$opened" == "NO" ]]; then
  echo "measure-cpu.sh: the panel did not appear to open: its figure is not clearly above the Orbit alone in normal. Check that the display is awake and unlocked." >&2
fi

exit "$status"
