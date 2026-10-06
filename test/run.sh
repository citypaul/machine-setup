#!/usr/bin/env bash
# Run the bats suite. Usage: test/run.sh [bats args…]   (default: every test/*.bats, in name order)
# Mutating tests (10-, 20-, 30-, 40-) only run with MACHINE_SETUP_ALLOW_MUTATION=1 on a disposable machine.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BATS_BIN=${BATS_BIN:-$(command -v bats || true)}
if [ -z "$BATS_BIN" ]; then
  CACHE="$ROOT/.cache/bats-core"
  if [ ! -x "$CACHE/bin/bats" ]; then
    git clone -q --depth 1 --branch v1.12.0 https://github.com/bats-core/bats-core "$CACHE"
  fi
  BATS_BIN="$CACHE/bin/bats"
fi
cd "$ROOT"
if [ $# -eq 0 ]; then set -- test; fi
exec "$BATS_BIN" --print-output-on-failure --timing "$@"
