#!/usr/bin/env bats
# Gates 1 (pre-existing Homebrew state), 5 (representative casks) and 6 (settings merge) on a real
# machine, plus the first converge. MUTATING: runs bootstrap.sh in place against this checkout.
load helpers

setup() { require_mutation; }

as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi; }
mise_in_checkout() { (cd "$REPO_ROOT" && "$HOME/.local/bin/mise" "$@"); }

@test "arrange pre-existing state: an undeclared package and, where Homebrew exists, a Homebrew-owned declared cask" {
  if is_macos; then
    command -v brew >/dev/null 2>&1 || skip "no Homebrew on this Mac yet (clean machine): bootstrap installs it"
    brew list hello >/dev/null 2>&1 || brew install hello
    [ -d /Applications/Ghostty.app ] || brew install --cask ghostty
    stat -f %m /Applications/Ghostty.app > "$BATS_FILE_TMPDIR/ghostty.mtime"
  else
    as_root apt-get install -y sl >/dev/null
    dpkg -s sl >/dev/null
  fi
}

@test "bootstrap sets up a fresh machine: mise installed, groups linked, packages present, state converged" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile personal --role desktop --machine studio --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"envs=personal,desktop,machine-studio"* ]]
  [ -x "$HOME/.local/bin/mise" ]
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/zsh/.zshrc" ]
  [ "$(readlink "$HOME/.config/ghostty/config")" = "$REPO_ROOT/ghostty/.config/ghostty/config" ]
  run mise_in_checkout bootstrap status --missing
  [ "$status" -eq 0 ]
}

@test "the representative casks are installed (macOS)" {
  skip_unless_macos
  local app
  for app in 1Password Ghostty "Visual Studio Code"; do
    [ -d "/Applications/$app.app" ] || { echo "missing /Applications/$app.app"; return 1; }
  done
  [ -x /opt/homebrew/bin/code ]
}

@test "a Homebrew-owned declared cask was counted as installed and left untouched (macOS)" {
  skip_unless_macos
  [ -f "$BATS_FILE_TMPDIR/ghostty.mtime" ] || skip "no pre-existing Homebrew state on this machine"
  [ "$(stat -f %m /Applications/Ghostty.app)" = "$(cat "$BATS_FILE_TMPDIR/ghostty.mtime")" ]
  run bash -c "cd '$REPO_ROOT' && '$HOME/.local/bin/mise' bootstrap packages status --json | jq -r '.\"brew-cask\".packages[] | select(.package==\"ghostty\") | .state'"
  [ "$output" = "installed" ]
}

@test "undeclared software survives bootstrap" {
  if is_macos; then
    command -v brew >/dev/null 2>&1 || skip "no pre-existing Homebrew state on this machine"
    brew list hello >/dev/null
  else
    dpkg -s sl >/dev/null
  fi
}

@test "the personal-only app is installed" {
  if is_macos; then [ -d /Applications/Spotify.app ]; else dpkg -s cmatrix >/dev/null; fi
}

@test "~/.claude/settings.json carries the repo settings" {
  jq -e '.model == "opus"' "$HOME/.claude/settings.json"
}

@test "running bootstrap again without flags reuses the selection and changes nothing" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"envs=personal,desktop,machine-studio"* ]]
  run mise_in_checkout bootstrap status --missing
  [ "$status" -eq 0 ]
}
