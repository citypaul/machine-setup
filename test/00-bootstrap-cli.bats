#!/usr/bin/env bats
# bootstrap.sh command-line contract: detection, validation, and the saved per-machine selection.
# Non-mutating: everything runs with --select-only against a private copy of the checkout.
load helpers

setup() {
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  export PATH="$FIXTURES/bin/op-unlocked:$PATH"
}

@test "an unsupported --os-family is rejected with exit 2 before anything is written" {
  skip_unless_linux
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --os-family rhel --profile work --machine studio --select-only --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"unsupported"* ]]
  [ ! -e "$CO/.miserc.local.toml" ]
  [ ! -e "$CO/mise.local.toml" ]
}

@test "--os-family is rejected on macOS, where there is no distro family" {
  skip_unless_macos
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --os-family debian --profile work --machine studio --select-only --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"--os-family"* ]]
}

@test "an unknown profile is rejected with exit 2" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile gaming --machine studio --select-only --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"profile"* ]]
  [ ! -e "$CO/.miserc.local.toml" ]
}

@test "a non-interactive run with no saved selection and no --profile fails with exit 2 and names the flag" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --machine studio --select-only --yes </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--profile"* ]]
}

@test "a non-interactive run with no --machine fails with exit 2 and names the flag" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --select-only --yes </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--machine"* ]]
}

@test "--select-only records profile, roles, machine, dotfiles.root and the env list without running mise" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop --role conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"envs=personal,desktop,conquer,machine-studio"* ]]
  [ "$(env_list_of "$CO")" = "personal,desktop,conquer,machine-studio" ]
  grep -q '^profile = "personal"$' "$CO/mise.local.toml"
  grep -q '^roles = "desktop conquer"$' "$CO/mise.local.toml"
  grep -q '^machine = "studio"$' "$CO/mise.local.toml"
  grep -q "^dotfiles.root = \"$CO\"$" "$CO/mise.local.toml"
}

@test "roles may also be given as one comma-separated list" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop,conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [ "$(env_list_of "$CO")" = "personal,desktop,conquer,machine-studio" ]
}

@test "the detected OS, family and architecture are printed" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile work --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  if is_macos; then
    [[ "$output" == *"os=macos"* ]]
  else
    [[ "$output" == *"os=linux"*"family=debian"* ]]
  fi
  [[ "$output" == *"arch="* ]]
}

@test "re-running without flags reuses the saved selection" {
  "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop --machine studio --select-only --yes >/dev/null
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --select-only --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"envs=personal,desktop,machine-studio"* ]]
}

@test "changing only --profile keeps the saved roles and machine" {
  "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop --machine studio --select-only --yes >/dev/null
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile work --select-only --yes
  [ "$status" -eq 0 ]
  [ "$(env_list_of "$CO")" = "work,desktop,machine-studio" ]
}

# A daemon started during a run (the 1Password CLI starts one when its cask generates completions)
# inherits every descriptor the run had. bats waits for EOF on fd 3, so a held descriptor hung the
# macOS CI job after its last test until the timeout (ADR 0001 F-41). mise and op must get stdio only.
prerequisites_present() {
  if is_macos; then xcode-select -p >/dev/null 2>&1 && [ -x /opt/homebrew/bin/brew ]
  else command -v git >/dev/null && command -v curl >/dev/null && [ -e /etc/ssl/certs/ca-certificates.crt ]; fi
}

@test "mise bootstrap runs with stdio only, so a daemon an installer starts cannot hold the caller's pipe open" {
  prerequisites_present || skip "prerequisites missing here; this test must not install them"
  { true >&3; } 2>/dev/null || skip "no descriptor 3 to leak in this harness"
  mkdir -p "$HOME/.local/bin"
  cp "$FIXTURES/bin/fd-probe/mise" "$HOME/.local/bin/mise"
  export FAKE_MISE_VERSION; FAKE_MISE_VERSION=$(sed -n 's/^MISE_PIN="\${MISE_VERSION:-v\([^}]*\)}"$/\1/p' "$REPO_ROOT/bootstrap.sh")
  export FD_PROBE="$BATS_TEST_TMPDIR/fd-probe"
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --machine studio --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$FD_PROBE")" = "open: none" ]
}

@test "the 1Password sign-in check runs op with stdio only" {
  { true >&3; } 2>/dev/null || skip "no descriptor 3 to leak in this harness"
  sed -i.bak 's/^secret_envs = ".*"$/secret_envs = "conquer"/' "$CO/mise.toml"
  export PATH="$FIXTURES/bin/fd-probe:$PATH" FD_PROBE="$BATS_TEST_TMPDIR/fd-probe"
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$FD_PROBE")" = "open: none" ]
}
