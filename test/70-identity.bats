#!/usr/bin/env bats
# Slice 6: identity (plan.md §4.6). Git identity rendered per profile from a template, a global
# gitignore, GPG configuration with the right pinentry per OS and the public keys imported, the
# YubiKey-aware signing wrapper, and an ssh config that uses the 1Password agent on every machine (D-21).
# Runs after 10-bootstrap.bats.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
  cd "$HOME"
}

mise_run() { (cd "$REPO_ROOT" && "$HOME/.local/bin/mise" "$@"); }
current_profile() { sed -n 's/^profile = "\(.*\)"$/\1/p' "$REPO_ROOT/mise.local.toml"; }

@test "git identity is rendered for the personal profile and includes a local override file" {
  [ "$(current_profile)" = personal ] || "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile personal --yes >/dev/null
  [ "$(git config --global user.name)" = "Paul Hammond" ]
  [ "$(git config --global user.email)" = "paul.hammond@gmail.com" ]
  [ "$(git config --global pull.rebase)" = "true" ]
  [ "$(git config --global init.defaultBranch)" = "main" ]
  [ "$(git config --global alias.recent)" != "" ]
  grep -q 'path = ~/.gitconfig.local' "$HOME/.gitconfig"
  [ "$(git config --global core.excludesfile)" = "~/.global_gitignore" ]
  [ -e "$HOME/.global_gitignore" ]
}

@test "the git email is the same for every profile and --git-email overrides it on this machine" {
  "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile work --yes >/dev/null
  [ "$(git config --global user.email)" = "paul.hammond@gmail.com" ]
  "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --profile personal --git-email paul@example.com --yes >/dev/null
  [ "$(git config --global user.email)" = "paul@example.com" ]
  "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --git-email '' --yes >/dev/null
  [ "$(git config --global user.email)" = "paul.hammond@gmail.com" ]
}

@test "GPG configuration is private, uses this OS's pinentry, and has the public keys imported" {
  [ "$(stat -f %Lp "$HOME/.gnupg" 2>/dev/null || stat -c %a "$HOME/.gnupg")" = "700" ]
  [ "$(stat -f %Lp "$HOME/.gnupg/gpg-agent.conf" 2>/dev/null || stat -c %a "$HOME/.gnupg/gpg-agent.conf")" = "600" ]
  local pinentry; pinentry=$(sed -n 's/^pinentry-program //p' "$HOME/.gnupg/gpg-agent.conf")
  [ -x "$pinentry" ] || { echo "pinentry $pinentry missing"; return 1; }
  grep -q 'keyid-format 0xlong' "$HOME/.gnupg/gpg.conf"
  run zsh -lc 'gpg --list-keys 0xF65FC25E09455075'
  [ "$status" -eq 0 ]
}

@test "the signing wrapper is installed and gpg-setup without a YubiKey explains instead of failing" {
  [ -x "$HOME/.local/bin/gpg-auto-sign" ]
  run mise_run run gpg-setup
  [ "$status" -eq 0 ]
  if [[ "$output" == *"no YubiKey"* ]]; then
    [ -z "$(git config --global user.signingkey || true)" ]
  else
    [ -n "$(git config --global user.signingkey)" ]
    [ "$(git config --global gpg.program)" = "$HOME/.local/bin/gpg-auto-sign" ]
  fi
}

@test "ssh config is private, includes a local drop-in directory, and points at the 1Password agent on every machine" {
  [ "$(stat -f %Lp "$HOME/.ssh/config" 2>/dev/null || stat -c %a "$HOME/.ssh/config")" = "600" ]
  grep -q 'Include ~/.ssh/config.d/\*' "$HOME/.ssh/config"
  [ -d "$HOME/.ssh/config.d" ]
  if is_macos; then
    grep -q 'IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.group.com.1password/t/agent.sock"' "$HOME/.ssh/config"
  else
    grep -q 'IdentityAgent ~/.1password/agent.sock' "$HOME/.ssh/config"
  fi
  run ssh -G localhost
  [ "$status" -eq 0 ]
  [[ "$output" == *"identityagent"* ]]
}
