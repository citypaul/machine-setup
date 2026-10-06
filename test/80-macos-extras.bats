#!/usr/bin/env bats
# Slice 7: macOS extras. Finder, keyboard and panel preferences are declared and applied by mise;
# the desktop role pins the Dock, installs the iTerm2 profile, the Alacritty theme and Talat. Runs
# after 10-bootstrap.bats (and 60-conquer.bats, which adds the desktop role on the test machines).
load helpers

setup() {
  require_mutation
  skip_unless_macos
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
  cd "$HOME"
}

has_desktop_role() { grep -q '^roles = ".*desktop' "$REPO_ROOT/mise.local.toml"; }

@test "Finder and keyboard preferences are applied and reported as current" {
  [ "$(defaults read com.apple.finder ShowPathbar)" = "1" ]
  [ "$(defaults read com.apple.finder FXPreferredViewStyle)" = "Nlsv" ]
  [ "$(defaults read com.apple.finder NewWindowTarget)" = "PfHm" ]
  [ "$(defaults read NSGlobalDomain AppleShowAllExtensions)" = "1" ]
  [ "$(defaults read NSGlobalDomain KeyRepeat)" = "0" ]
  [ "$(defaults read NSGlobalDomain AppleKeyboardUIMode)" = "3" ]
  [ "$(defaults read com.apple.Terminal NewTabWorkingDirectoryBehavior)" = "1" ]
  run mise_in_checkout bootstrap macos defaults status --missing
  [ "$status" -eq 0 ]
  run ls -lOd "$HOME/Library"
  [[ "$output" != *"hidden"* ]]
}

@test "the desktop role pins the declared apps in the Dock, in order" {
  has_desktop_role || skip "desktop role not selected on this machine"
  run defaults read com.apple.dock persistent-apps
  [ "$status" -eq 0 ]
  local labels; labels=$(printf '%s\n' "$output" | sed -n 's/.*"file-label" = "\{0,1\}\([^";]*\)"\{0,1\};/\1/p' | tr '\n' ',')
  [[ "$labels" == "Fantastical,Alacritty,Ghostty,Cursor,"* ]]
  [[ "$labels" == *"Claude,FluidVoice,Obsidian,"* ]]
}

@test "the desktop role installs the iTerm2 dynamic profile and the Alacritty theme the config imports" {
  has_desktop_role || skip "desktop role not selected on this machine"
  plutil -lint "$HOME/Library/Application Support/iTerm2/DynamicProfiles/machine-setup.json" >/dev/null
  [ "$(file_mode "$HOME/Library/Application Support/iTerm2/DynamicProfiles/machine-setup.json")" = "644" ]
  [ -f "$HOME/.config/alacritty/themes/themes/night_owl.toml" ]
  [ "$(readlink "$HOME/.alacritty.toml")" = "$REPO_ROOT/alacritty/.alacritty.toml" ]
}

@test "Talat is installed from its release feed on Apple Silicon with the desktop role, once" {
  has_desktop_role || skip "desktop role not selected on this machine"
  [ "$(uname -m)" = arm64 ] || skip "Talat ships Apple Silicon builds only"
  [ -d /Applications/Talat.app ]
  codesign -dv /Applications/Talat.app 2>&1 | grep -qx 'TeamIdentifier=X37TLUX6CW'
  run mise_in_checkout run talat
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "the talat task does nothing without the desktop role or on another platform" {
  run "$REPO_ROOT/tasks/talat" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}
