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
