#!/usr/bin/env bats
# `machine-setup`: this checkout's everyday commands from any directory (ADR 0001 D-48). The bin
# dotfile group links it into ~/.local/bin on every machine, so it finds the checkout through its own
# link. Safe: the checkout is a private clone of a private "origin", and bootstrap.sh and mise are
# stand-ins that log how they were called and from where. Numbered after 10-bootstrap although it
# changes nothing on the machine: it needs git, which a clean Linux machine has only once bootstrap
# has run, and there /bin/sh is dash, the shell this command most needs testing under.
load helpers
bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  require_git
  fresh_home
  export CALL_LOG="$BATS_TEST_TMPDIR/calls"
  ORIGIN="$BATS_TEST_TMPDIR/origin"
  copy_checkout "$ORIGIN"
  printf '#!/bin/sh\necho "bootstrap.sh $* (in $PWD)" >> "$CALL_LOG"\n' > "$ORIGIN/bootstrap.sh"
  chmod +x "$ORIGIN/bootstrap.sh"
  origin_git init -q -b main
  origin_git add -A
  origin_git commit -q -m "first"
  CO="$BATS_TEST_TMPDIR/checkout"
  git clone -q "$ORIGIN" "$CO"
  REAL_CO=$(cd "$CO" && pwd -P)
  export MISE_BIN="$BATS_TEST_TMPDIR/mise"
  printf '#!/bin/sh\necho "mise $* (in $PWD)" >> "$CALL_LOG"\n' > "$MISE_BIN"
  chmod +x "$MISE_BIN"
  # Linked the way mise's symlink-each mode links it, then run from somewhere else.
  mkdir -p "$HOME/.local/bin" "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$CO/dotfiles/bin/.local/bin/machine-setup" "$HOME/.local/bin/machine-setup"
  cd "$BATS_TEST_TMPDIR/elsewhere"
  CLI="$HOME/.local/bin/machine-setup"
}
origin_git() { git -C "$ORIGIN" -c user.name=test -c user.email=test@example.invalid "$@"; }
# A new commit on origin's main: the change a self-update fetches.
publish() { echo "$1" >> "$ORIGIN/README.md"; origin_git commit -q -a -m "$1"; }
head_of() { git -C "$1" rev-parse HEAD; }

@test "update upgrades the computer: the update task runs inside the checkout with the flags given" {
  run "$CLI" update --dry-run
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "mise run update -- --dry-run (in $REAL_CO)" ]
}

@test "check runs check-machine inside the checkout and passes its exit status back" {
  run "$CLI" check
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "mise run check-machine (in $REAL_CO)" ]
  printf '#!/bin/sh\nexit 1\n' > "$MISE_BIN"
  run "$CLI" check
  [ "$status" -eq 1 ]
}

@test "converge runs bootstrap for this checkout without questions, with the flags given" {
  run "$CLI" converge --dry-run
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "bootstrap.sh --dir $REAL_CO --yes --dry-run (in $REAL_CO)" ]
}

@test "self-update brings the checkout, and so the command itself, to origin's newest commit and says to converge" {
  publish "a newer machine-setup"
  [ "$(head_of "$CO")" != "$(head_of "$ORIGIN")" ]
  run "$CLI" self-update
  [ "$status" -eq 0 ]
  [ "$(head_of "$CO")" = "$(head_of "$ORIGIN")" ]
  [[ "$output" == *"a newer machine-setup"* ]] || false
  [[ "$output" == *"machine-setup converge"* ]] || false
  [ ! -e "$CALL_LOG" ]   # it updates the command only: nothing on the computer is converged or upgraded
}

@test "self-update --dry-run lists what would arrive and leaves the checkout as it is" {
  publish "a newer machine-setup"
  local before; before=$(head_of "$CO")
  run "$CLI" self-update --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"a newer machine-setup"* ]] || false
  [ "$(head_of "$CO")" = "$before" ]
}

@test "self-update with nothing new says so and succeeds" {
  run "$CLI" self-update
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]] || false
}

@test "self-update stops with exit 1 and a way forward when the checkout has commits origin does not" {
  publish "a newer machine-setup"
  echo local >> "$CO/README.md"
  git -C "$CO" -c user.name=test -c user.email=test@example.invalid commit -q -a -m "a local change"
  local before; before=$(head_of "$CO")
  run "$CLI" self-update
  [ "$status" -eq 1 ]
  [[ "$output" == *"error:"*"cannot fast-forward"* ]] || false
  [[ "$output" == *"git -C $REAL_CO status"* ]] || false
  [ "$(head_of "$CO")" = "$before" ]
}

@test "--version names the commit and the checkout in use" {
  run "$CLI" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "machine-setup $(git -C "$CO" rev-parse --short HEAD) "*"$REAL_CO" ]] || false
}

@test "no command, --help and help list the commands and exit codes on stdout" {
  for args in "" "--help" "help"; do
    # shellcheck disable=SC2086  # no argument at all is one of the cases
    run "$CLI" $args
    [ "$status" -eq 0 ]
    [[ "$output" == *"update"*"self-update"*"check"*"converge"*"Exit codes"* ]] || false
  done
  [ ! -e "$CALL_LOG" ]
}

@test "an unknown command or flag is refused with exit 2 on stderr, and nothing runs" {
  run --separate-stderr "$CLI" nonsense
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"error: unknown command: nonsense"* ]] || false
  run --separate-stderr "$CLI" self-update --bogus
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"error: unknown flag for self-update: --bogus"* ]] || false
  [ ! -e "$CALL_LOG" ]
}
