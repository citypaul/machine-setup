#!/usr/bin/env bats
# Slice 9: `doctor` (the checks mise does not make: selection, drift, login shell, 1Password, Conquer,
# the GPG card, the skills pin) and `update` (upgrade on purpose, with the plan shown first). Safe:
# a private copy of the checkout, a fresh HOME and the fake op and tailscale binaries.
load helpers

setup() {
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  fresh_home
  # Fakes first, always: these tests run anywhere, including a workstation with a real 1Password,
  # YubiKey and Tailscale, and must never touch them.
  export PATH="$FIXTURES/bin/op-locked:$FIXTURES/bin/gpg-nocard:$PATH"
}

# doctor and update need mise for every check after the first; CI installs it in 10-bootstrap.
with_mise() { require_mise; export MISE_BIN; MISE_BIN=$(mise_bin); }

@test "doctor fails on a checkout with no saved selection and says to run bootstrap" {
  with_mise
  run "$CO/tasks/doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"*"selection"* ]] || false
  [[ "$output" == *"bootstrap.sh"* ]] || false
}

@test "doctor fails when mise itself is missing, before anything else" {
  [ ! -x "$HOME/.local/bin/mise" ] || skip "this HOME has mise"
  select_envs "$CO" personal - studio >/dev/null
  MISE_BIN= PATH="$FIXTURES/bin/op-locked:/usr/bin:/bin" run "$CO/tasks/doctor"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"FAIL"*"mise"* ]] || false
}

@test "doctor reports a locked 1Password as a warning, never a failure" {
  with_mise
  select_envs "$CO" personal - studio >/dev/null
  run "$CO/tasks/doctor"
  [[ "$output" == *"WARN"*"1Password"*"not signed in"* ]] || false
  ! grep -q "FAIL.*1Password" <<<"$output" || false
}

@test "doctor reports the Conquer state from tailscale only when the role is selected" {
  with_mise
  # Without the role first: a re-run without --role keeps the saved roles, so the order matters.
  select_envs "$CO" personal - studio >/dev/null
  PATH="$FIXTURES/bin/tailscale-connected:$PATH" run "$CO/tasks/doctor"
  [[ "$output" != *"Tailscale"* ]] || false
  select_envs "$CO" personal conquer studio >/dev/null
  PATH="$FIXTURES/bin/tailscale-needs-login:$PATH" run "$CO/tasks/doctor"
  [[ "$output" == *"WARN"*"Tailscale"*"login"* ]] || false
  PATH="$FIXTURES/bin/tailscale-connected:$PATH" run "$CO/tasks/doctor"
  [[ "$output" == *"OK"*"Tailscale"*"connected"* ]] || false
}

@test "doctor ends with a summary line and exits 1 while the checkout has never been converged" {
  with_mise
  select_envs "$CO" personal - studio >/dev/null
  run "$CO/tasks/doctor"
  [ "$status" -eq 1 ]
  [[ "${lines[${#lines[@]}-1]}" == doctor:*checks*failed* ]] || false   # bash 3.2: no negative index
  [[ "$output" == *"FAIL"*"drift"* ]] || false
}

@test "update --dry-run shows the package and tool upgrade plan and changes nothing; unknown flags are refused" {
  with_mise
  select_envs "$CO" personal - studio >/dev/null
  run "$CO/tasks/update" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"update: packages"* ]] || false
  [[ "$output" == *"update: tools"* ]] || false
  [[ "$output" == *"update: skills pinned to v"* ]] || false
  [[ "$output" == *"dry run"* ]] || false
  run "$CO/tasks/update" --bogus
  [ "$status" -eq 2 ]
}

@test "update without --yes and without a terminal applies nothing and says how to" {
  with_mise
  select_envs "$CO" personal - studio >/dev/null
  run "$CO/tasks/update" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]] || false
}

@test "doctor warns when this session's SHELL is not the login shell, so terminals that read SHELL get the wrong one" {
  # Found on the fresh Ubuntu VM: the install made zsh the login shell, but the desktop session kept
  # SHELL=/bin/bash, so Ghostty and Alacritty opened bash without the aliases or fzf (ADR 0001 F-51).
  with_mise
  local login
  if is_macos; then login=$(dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}'); else login=$(getent passwd "$(id -un)" | cut -d: -f7); fi
  [[ "$login" == */zsh ]] || skip "the login shell here is $login, not zsh"
  select_envs "$CO" personal - studio >/dev/null
  SHELL=/bin/sh run "$CO/tasks/doctor"
  [[ "$output" == *"WARN"*"SHELL is /bin/sh"*"log out and back in"* ]] || false
  SHELL="$login" run "$CO/tasks/doctor"
  [[ "$output" != *"SHELL is"* ]] || false
}
