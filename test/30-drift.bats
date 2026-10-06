#!/usr/bin/env bats
# Drift repair: deleting a managed file or a declared package is reported by status and repaired
# by the next converge without upgrading anything. Runs after 10-bootstrap.bats.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
}

as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi; }
status_missing() { (cd "$REPO_ROOT" && "$HOME/.local/bin/mise" bootstrap status --missing >/dev/null 2>&1); }
converge() { "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --yes >/dev/null; }

@test "a deleted managed dotfile is drift and converge restores it" {
  rm "$HOME/.zshrc"
  ! status_missing
  converge
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/zsh/.zshrc" ]
  status_missing
}

@test "a removed declared package is drift and converge reinstalls it" {
  if is_macos; then
    brew uninstall tree >/dev/null 2>&1 || rm -rf /opt/homebrew/Cellar/tree /opt/homebrew/opt/tree /opt/homebrew/bin/tree
    ! status_missing
    converge
    [ -x /opt/homebrew/bin/tree ]
  else
    as_root apt-get remove -y tree >/dev/null
    ! status_missing
    converge
    dpkg -s tree >/dev/null
  fi
  status_missing
}
