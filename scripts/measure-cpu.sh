#!/usr/bin/env bash
# Measures the CPU Ian's own process uses in a Release build against the mock (P1, spec 6.9):
# the Orbit alone in `quiet`, `normal` and `incident`, and the expanded client open on Today in
# `normal`. CPU is the change in the process's cumulative CPU time over 30 seconds, after a
# 10-second warm-up. Prints one table and exits non-zero when a target is missed.
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
# The app's mock profile is fixed at port 4317, so the port cannot change.
port=4317
base="http://127.0.0.1:$port"
derived_data="$repo_root/build/DerivedDataRelease"
app_bin="$derived_data/Build/Products/Release/Ian.app/Contents/MacOS/Ian"
warm_up=10
window=30
orbit_target=0.7
panel_target=10

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
build_log=""
mock_children=""
app_pid=""
mock_log="$(mktemp -t ian-measure-mock.XXXXXX)"

stop_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || return 0
  for _ in $(seq 1 25); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  kill -9 "$pid" 2>/dev/null || true
}

stop_app() {
  stop_pid "$app_pid"
  app_pid=""
}

# Stops what this script started, by pid, and reports anything that is still running.
cleanup() {
  local status=$?
  trap - EXIT
  stop_app
  local child
  for child in $mock_children; do stop_pid "$child"; done
  stop_pid "$mock_pid"
  stop_pid "$caffeinate_pid"
  rm -f "$mock_log" "$build_log"
  sleep 0.5
  if pgrep -f "$app_bin" >/dev/null; then
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

# A sleeping display, a screen lock or a screen saver would occlude the Orbit and the panel, which
# stops their animation and makes the figures meaninglessly low. `-w` ends it with this script.
caffeinate -d -i -w $$ &
caffeinate_pid=$!
disown "$caffeinate_pid"

echo "Building Ian in Release. The first build takes a few minutes."
build_log="$(mktemp -t ian-measure-build.XXXXXX)"
if ! xcodebuild -project "$repo_root/App/Ian.xcodeproj" -scheme Ian -configuration Release \
  -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath "$derived_data" build >"$build_log" 2>&1; then
  tail -n 30 "$build_log" >&2
  fail "the Release build failed. The last lines of its log are above."
fi
[[ -x "$app_bin" ]] || fail "the build did not produce $app_bin."

MOCK_PORT="$port" "$repo_root/scripts/dev.sh" --mock-only >"$mock_log" 2>&1 &
mock_pid=$!
# Disowned, so bash does not print a "Terminated" notice when the cleanup stops it.
disown "$mock_pid"
ready=0
for _ in $(seq 1 100); do
  if grep -q '^Mock listening' "$mock_log"; then
    ready=1
    break
  fi
  kill -0 "$mock_pid" 2>/dev/null || {
    cat "$mock_log" >&2
    fail "the mock stopped while starting."
  }
  sleep 0.2
done
[[ "$ready" == "1" ]] || fail "the mock did not report that it was listening within twenty seconds."
for _ in $(seq 1 25); do
  curl -s -o /dev/null --max-time 1 "$base/__mock/sessions" && break
  sleep 0.2
done
mock_children="$(pgrep -P "$mock_pid" || true)"

set_scenario() {
  curl -sf -o /dev/null -X POST -H 'content-type: application/json' \
    -d "{\"scenario\":\"$1\"}" "$base/__mock/scenario" ||
    fail "the mock did not accept the scenario '$1'."
}

# Starts Ian on the mock, with any extra launch arguments, and waits until it holds a connection.
launch_app() {
  "$app_bin" -IanEnvironment mock "$@" >/dev/null 2>&1 &
  app_pid=$!
  disown "$app_pid"
  # The child shows the shell's command line until it has executed, so give it a second.
  local command=""
  for _ in $(seq 1 10); do
    command="$(ps -o command= -p "$app_pid" 2>/dev/null || true)"
    [[ "$command" == "$app_bin"* ]] && break
    sleep 0.1
  done
  [[ "$command" == "$app_bin"* ]] ||
    fail "pid $app_pid is not Ian's binary (its command is '$command')."
  for _ in $(seq 1 100); do
    kill -0 "$app_pid" 2>/dev/null || fail "Ian exited while starting."
    if lsof -nP -a -p "$app_pid" -iTCP@127.0.0.1:"$port" -sTCP:ESTABLISHED 2>/dev/null |
      grep -q ESTABLISHED; then
      return 0
    fi
    sleep 0.2
  done
  fail "Ian held no connection to the mock within twenty seconds."
}

# Cumulative CPU time of the app in seconds, from ps's [[hh:]mm:]ss.cc form.
cpu_seconds() {
  ps -o time= -p "$1" | awk '{ n = split($1, p, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + p[i]; print s }'
}

now() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# Prints Ian's CPU percentage and WindowServer's over the measuring window.
measure() {
  sleep "$warm_up"
  kill -0 "$app_pid" 2>/dev/null || fail "Ian exited during the warm-up."
  local cpu_before time_before cpu_after time_after ws_before ws_after
  cpu_before="$(cpu_seconds "$app_pid")"
  ws_before="$(cpu_seconds "$window_server_pid")"
  time_before="$(now)"
  sleep "$window"
  kill -0 "$app_pid" 2>/dev/null || fail "Ian exited during the measurement."
  cpu_after="$(cpu_seconds "$app_pid")"
  ws_after="$(cpu_seconds "$window_server_pid")"
  time_after="$(now)"
  awk -v c0="$cpu_before" -v c1="$cpu_after" -v w0="$ws_before" -v w1="$ws_after" \
    -v t0="$time_before" -v t1="$time_after" \
    'BEGIN { printf "%.2f %.2f\n", (c1 - c0) / (t1 - t0) * 100, (w1 - w0) / (t1 - t0) * 100 }'
}

window_server_pid="$(pgrep -x WindowServer | head -n 1 || true)"
[[ -n "$window_server_pid" ]] || fail "WindowServer is not running, so there is no display to measure."

echo "Measuring the Orbit alone."
launch_app
set_scenario quiet
result="$(measure)"
read -r quiet quiet_ws <<<"$result"
set_scenario normal
result="$(measure)"
read -r normal normal_ws <<<"$result"
set_scenario incident
result="$(measure)"
read -r incident incident_ws <<<"$result"
stop_app

echo "Measuring the panel open on Today."
set_scenario normal
launch_app -IanOpenPanelOnLaunch YES
result="$(measure)"
read -r panel panel_ws <<<"$result"
stop_app

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
for result in "$normal_verdict" "$incident_verdict" "$panel_verdict"; do
  [[ "$result" == "MISSED" ]] && status=1
done

echo
echo "Machine: $(sysctl -n machdep.cpu.brand_string) ($(sysctl -n hw.model)), $(sw_vers -productName) $(sw_vers -productVersion)"
echo "Release build, mock scenarios, ${window} s after a ${warm_up} s warm-up."
printf '%-30s %8s %10s %8s %14s\n' "State" "Ian CPU %" "Target" "Result" "WindowServer %"
printf '%-30s %8s %10s %8s %14s\n' "Orbit only, quiet" "$quiet" "none" "-" "$quiet_ws"
printf '%-30s %8s %10s %8s %14s\n' "Orbit only, normal" "$normal" "< $orbit_target" "$normal_verdict" "$normal_ws"
printf '%-30s %8s %10s %8s %14s\n' "Orbit only, incident" "$incident" "< $orbit_target" "$incident_verdict" "$incident_ws"
printf '%-30s %8s %10s %8s %14s\n' "Panel open on Today, normal" "$panel" "< $panel_target" "$panel_verdict" "$panel_ws"

if [[ "$opened" == "NO" ]]; then
  echo "measure-cpu.sh: the panel did not appear to open: its figure is not clearly above the Orbit alone in normal. Check that the display is awake and unlocked." >&2
fi

exit "$status"
