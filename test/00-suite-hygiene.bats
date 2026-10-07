#!/usr/bin/env bats
# The suite's own assertions must be enforced. bats under macOS's bash 3.2 ignores a failing [[ ]]
# that is not a test's last command, and no bash enforces `! cmd` under set -e, so each needs
# `|| false` (ADR 0001 F-49).
load helpers

@test "every [[ ]] and ! assertion in the suite is enforced with || false" {
  run grep -nE '^[[:space:]]*(\[\[.*\]\]|! .*)([[:space:]]+#.*)?$' "$REPO_ROOT"/test/*.bats
  unguarded=$(printf '%s\n' "$output" | grep -v '||' || true)
  [ -z "$unguarded" ] || { echo "unenforced assertions:"; echo "$unguarded"; return 1; }
}
