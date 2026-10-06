#!/usr/bin/env bats
# Gates 2 and 3: dotfile-group composition across env files and machine-file discovery.
# Also: personal-only apps never appear in a work selection; removal lists compose across layers.
# Non-mutating: reads the effective configuration with a fresh HOME.
load helpers

setup() {
  require_mise
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  select_envs "$CO" personal desktop studio >/dev/null
}

# Group roots deployed for an env selection, as space-separated basenames.
groups_for() {
  (cd "$CO" && mise -E "$1" dot status --json 2>/dev/null | jq -r '.files[].source | split("/") | last' | sort | tr '\n' ' ' | sed 's/ $//')
}

# Every package name the effective configuration declares for an env selection.
packages_for() {
  (cd "$CO" && mise -E "$1" bootstrap packages status --json 2>/dev/null | jq -r '.. | objects | select(has("package")) | .package' | sort -u)
}

@test "the machine file is loaded by its env name, also when mise is invoked from outside the checkout" {
  run mise -C "$CO" -E personal,desktop,machine-studio config ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise.machine-studio.toml"* ]]
}

@test "the saved selection is honoured from inside the checkout" {
  run bash -c "cd '$CO' && '$(mise_bin)' config ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise.personal.toml"* ]]
  [[ "$output" == *"mise.desktop.toml"* ]]
  [[ "$output" == *"mise.machine-studio.toml"* ]]
}

@test "machine-studio deploys both the zsh and the ghostty groups" {
  [ "$(groups_for personal,desktop,machine-studio)" = "ghostty zsh" ]
}

@test "the desktop role without a machine file still deploys zsh: group lists replace, so a role states the full list" {
  [ "$(groups_for personal,desktop)" = "ghostty zsh" ]
}

@test "the work profile without roles deploys zsh only" {
  [ "$(groups_for work)" = "zsh" ]
}

@test "every machine file yields a non-empty group list containing zsh" {
  local f env groups
  for f in "$CO"/mise.machine-*.toml; do
    env=$(basename "$f" .toml); env=${env#mise.}
    groups=$(groups_for "personal,$env")
    [[ " $groups " == *" zsh "* ]] || { echo "$env -> '$groups'"; return 1; }
  done
}

@test "a personal-only app is declared for personal and absent from work" {
  local app
  if is_macos; then app=spotify; else app=cmatrix; fi
  packages_for personal | grep -qx "$app"
  ! packages_for work | grep -qx "$app"
}

@test "the removal allowlist composes across the profile and machine layers" {
  run bash -c "cd '$CO' && '$(mise_bin)' -E work,machine-studio run remove-packages --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spotify"* && "$output" == *"discord"* && "$output" == *"jellyfin"* ]]
  [[ "$output" == *"cmatrix"* ]]
  run bash -c "cd '$CO' && '$(mise_bin)' -E personal,machine-studio run remove-packages --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" != *"spotify"* ]]
}
