#!/usr/bin/env bats
# Gate 1: layered removal with mixed Homebrew ownership. Switching an already-set-up personal
# machine to the work profile removes exactly the declared personal apps and nothing else.
# Runs last: it changes the machine's profile.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
}


@test "switching to the work profile removes the personal apps and leaves undeclared software alone" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile work --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"envs=work,"*"machine-${MACHINE_SETUP_TEST_MACHINE:-vm}"* ]] || false   # roles may be carried over from an earlier selection
  if is_macos; then
    [ ! -d /Applications/Spotify.app ]
    [ -d /Applications/1Password.app ]
    [ -d /Applications/Ghostty.app ]
    [ -d "/Applications/Visual Studio Code.app" ]
  else
    ! dpkg -s cmatrix >/dev/null 2>&1 || false
  fi
  # Undeclared software survives: only checkable when 10-bootstrap arranged some in this run.
  if [ -f "$BATS_RUN_TMPDIR/arranged" ]; then
    if is_macos; then brew list hello >/dev/null; else dpkg -s sl >/dev/null; fi
  fi
  converged
}

@test "switching back to personal reinstalls the personal apps" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile personal --yes
  [ "$status" -eq 0 ]
  if is_macos; then [ -d /Applications/Spotify.app ]; else dpkg -s cmatrix >/dev/null; fi
  converged
}
