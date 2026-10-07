#!/usr/bin/env bash
# Run the bats suite. Usage: test/run.sh [bats args…]   (default: every test/*.bats, in name order)
# Mutating tests (10- to 95-) only run with MACHINE_SETUP_ALLOW_MUTATION=1 on a disposable machine.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BATS_BIN=${BATS_BIN:-$(command -v bats || true)}
if [ -z "$BATS_BIN" ]; then
  CACHE="$ROOT/.cache/bats-core"
  if [ ! -x "$CACHE/bin/bats" ]; then
    # A tarball, not a clone: a clean Mac has no git until the Command Line Tools are installed.
    mkdir -p "$CACHE"
    curl -fsSL https://github.com/bats-core/bats-core/archive/refs/tags/v1.12.0.tar.gz | tar xz -C "$CACHE" --strip-components=1
  fi
  BATS_BIN="$CACHE/bin/bats"
fi
cd "$ROOT"
if [ $# -eq 0 ]; then set -- test; fi

# Guard against a known bats hang (ADR 0001 F-41): a daemon started by a test (gpg-agent, scdaemon, the
# 1Password CLI) keeps bats' descriptor 3 open, and bats waits for it, so a run whose tests all passed
# sat until the CI timeout. Once every planned test has reported, bats gets $grace seconds to exit;
# after that this names the likely holders and fails, in a minute instead of an hour.
grace=${MACHINE_SETUP_TEST_GRACE:-60}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/machine-setup-run.XXXXXX")
mkfifo "$tmp/out"
"$BATS_BIN" --print-output-on-failure --timing "$@" > "$tmp/out" 2>&1 &
bats_pid=$!
kill_tree() { local child; for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done; kill "$1" 2>/dev/null || true; }
trap 'kill_tree "$bats_pid"; rm -rf "$tmp"; exit 130' INT TERM
trap 'rm -rf "$tmp"' EXIT
exec 4< "$tmp/out"
planned=0 reported=0 hung=0
while :; do
  timed=0
  if [ "$planned" -gt 0 ] && [ "$reported" -ge "$planned" ]; then
    timed=1
    if IFS= read -r -t "$grace" line <&4; then rc=0; else rc=$?; fi
  else
    if IFS= read -r line <&4; then rc=0; else rc=$?; fi
  fi
  if [ "$rc" -ne 0 ]; then
    # macOS's bash 3.2 returns 1 for a timeout as well as for end of output: a bats still running
    # after a few seconds' grace means the read timed out.
    if [ "$timed" = 1 ]; then
      for _ in 1 2 3 4 5; do kill -0 "$bats_pid" 2>/dev/null || break; sleep 1; done
      if kill -0 "$bats_pid" 2>/dev/null; then hung=1; fi
    fi
    break
  fi
  printf '%s\n' "$line"
  case "$line" in
    1..*) planned=${line#1..} ;;
    "ok "*|"not ok "*) reported=$((reported + 1)) ;;
  esac
done
if [ "$hung" = 1 ]; then
  echo "run.sh: all $planned tests reported, but bats did not exit within ${grace}s: a process started by a test still holds its output (ADR 0001 F-41). Likely holders:" >&2
  # shellcheck disable=SC2009  # pgrep cannot print the elapsed time and full command portably
  ps -eo pid,ppid,etime,command 2>/dev/null | grep -E '[g]pg-agent|[s]cdaemon|[k]eyboxd|[d]irmngr|[o]p daemon|[h]erdr|[T]ailscale' >&2 || echo "  (none of the usual daemons; check ps)" >&2
  kill_tree "$bats_pid"
  exit 1
fi
wait "$bats_pid"
