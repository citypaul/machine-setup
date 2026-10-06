#!/usr/bin/env bats
# Gate 1: layered removal with mixed Homebrew ownership. Switching an already-set-up personal
# machine to the work profile removes exactly the declared personal apps and nothing else.
# Runs last: it changes the machine's profile.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
}

status_missing() { (cd "$REPO_ROOT" && "$HOME/.local/bin/mise" bootstrap status --missing >/dev/null 2>&1); }

@test "switching to the work profile removes the personal apps and leaves undeclared software alone" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile work --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"envs=work,desktop,machine-studio"* ]]
  if is_macos; then
    [ ! -d /Applications/Spotify.app ]
    [ -d /Applications/1Password.app ]
    if command -v brew >/dev/null 2>&1; then brew list hello >/dev/null; fi
  else
    ! dpkg -s cmatrix >/dev/null 2>&1
    dpkg -s sl >/dev/null
  fi
  status_missing
}

@test "switching back to personal reinstalls the personal apps" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile personal --yes
  [ "$status" -eq 0 ]
  if is_macos; then [ -d /Applications/Spotify.app ]; else dpkg -s cmatrix >/dev/null; fi
  status_missing
}
