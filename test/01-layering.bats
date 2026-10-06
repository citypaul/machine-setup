#!/usr/bin/env bats
# Gates 2 and 3: dotfile-group composition across env files and machine-file discovery.
# Also: personal-only apps never appear in a work selection; removal lists compose across layers.
# Non-mutating: reads the effective configuration with a fresh HOME.
load helpers

setup() {
  require_jq
  require_mise
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  select_envs "$CO" personal desktop studio >/dev/null
}

# Group roots deployed for an env selection, as space-separated basenames.
groups_for() {
  (cd "$CO" && mise -E "$1" dot status --json 2>/dev/null | jq -r '.files[] | select(.mode == "symlink-each") | .source | split("/") | last' | sort | tr '\n' ' ' | sed 's/ $//')
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
  [ "$(groups_for personal,desktop,machine-studio)" = "ghostty mise zsh" ]
}

@test "the desktop role without a machine file still deploys zsh: group lists replace, so a role states the full list" {
  [ "$(groups_for personal,desktop)" = "ghostty mise zsh" ]
}

@test "the work profile without roles deploys the zsh and mise groups only" {
  [ "$(groups_for work)" = "mise zsh" ]
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

# Package keys declared in one layer file, e.g. brew-cask:spotify, apt:cmatrix.
declared_in() { sed -n -E 's/^"((brew|brew-cask|apt|mas):[^"]+)".*/\1/p' "$CO/$1"; }
name_of() { printf '%s' "$1" | cut -d: -f2-; }
removal_plan_for() { (cd "$CO" && mise -E "$1" run remove-packages --dry-run 2>/dev/null); }

@test "every package declared in the personal layer is absent from the work selection" {
  local work key name
  work=$(packages_for work)
  [ -n "$(declared_in mise.personal.toml)" ]
  for key in $(declared_in mise.personal.toml); do
    name=$(name_of "$key")
    if grep -qx "$name" <<<"$work"; then echo "$name is declared for personal but present in work"; return 1; fi
  done
}

@test "the work removal allowlist names every personal-only cask, so switching profile removes them" {
  local plan key name
  plan=$(removal_plan_for work,machine-studio)
  for key in $(declared_in mise.personal.toml | grep '^brew-cask:'); do
    name=$(name_of "$key")
    [[ "$plan" == *"$name"* ]] || { echo "$name is personal-only but not on the work removal allowlist"; return 1; }
  done
}

@test "the legacy unwanted packages stay on every profile's removal allowlist" {
  local env plan p
  for env in personal work; do
    plan=$(removal_plan_for "$env,machine-studio")
    for p in neofetch arc orbstack wezterm karabiner-elements; do
      [[ "$plan" == *"$p"* ]] || { echo "$p missing from the $env allowlist"; return 1; }
    done
  done
}

@test "work-only removals do not apply to the personal profile" {
  local plan; plan=$(removal_plan_for personal,machine-studio)
  [[ "$plan" != *"brave-browser"* ]]
  [[ "$plan" != *"protonvpn"* ]]
}
