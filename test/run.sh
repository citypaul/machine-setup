#!/usr/bin/env bash
# Run the bats suite. Usage: test/run.sh [bats args…]   (default: every test/*.bats, in name order)
# Mutating tests (10-, 20-, 30-, 40-) only run with MACHINE_SETUP_ALLOW_MUTATION=1 on a disposable machine.
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
exec "$BATS_BIN" --print-output-on-failure --timing "$@"
