#!/usr/bin/env bats
# Claude Code profiles (citypaul/.dotfiles docs/claude-profiles.md): one config directory per profile,
# opt-in. Non-mutating: sources the checkout's zsh profile in a fresh HOME with a stub `claude` that
# prints the config directory it was given.
load helpers

setup() {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  fresh_home
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  printf '#!/bin/sh\nprintf "%%s|%%s\\n" "${CLAUDE_CONFIG_DIR-unset}" "$*"\n' > "$STUB/claude"
  chmod +x "$STUB/claude"
}

# Run zsh code after sourcing the profile, with the stub first on PATH.
profile_zsh() {
  env -u CLAUDE_CONFIG_DIR STUB="$STUB" zsh -fc 'path=("$STUB" $path); source "$1" 2>/dev/null; eval "$2"' zsh "$REPO_ROOT/dotfiles/zsh/.zsh_profile" "$1"
}

@test "claude-profile runs Claude with that profile's directory for one command, and plain claude is unchanged" {
  run profile_zsh 'claude --version; claude-profile work plugin list; claude --version'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "unset|--version" ]
  [ "${lines[1]}" = "$HOME/.claude-work|plugin list" ]
  [ "${lines[2]}" = "unset|--version" ]
}

@test "claude-profile without a name prints its usage, exits 2 and does not start Claude" {
  run profile_zsh 'claude-profile'
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: claude-profile"* ]] || false
  [[ "$output" != *"|"* ]] || false
}

@test "claude-personal uses the stock ~/.claude even when the machine default is another profile" {
  run profile_zsh 'export CLAUDE_CONFIG_DIR="$HOME/.claude-work"; claude --version; claude-personal --resume; claude --version'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$HOME/.claude-work|--version" ]
  [ "${lines[1]}" = "unset|--resume" ]
  [ "${lines[2]}" = "$HOME/.claude-work|--version" ]
}
