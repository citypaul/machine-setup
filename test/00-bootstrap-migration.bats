#!/usr/bin/env bats
# bootstrap.sh takes over a home that GNU Stow manages: one command shows the removal list, checks the
# migration with its dry run, migrates (journaled, tasks/migrate), then converges, once. A home with no
# Stow links is untouched by any of it. Non-mutating: fresh HOME, a private checkout whose
# tasks/migrate is a stub, a fake mise and fake sudo; every call lands in CALL_LOG in order.
load helpers

setup() {
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  export CALL_LOG="$BATS_TEST_TMPDIR/calls" FAKE_SUDO=passwordless FAKE_SUDO_STATE="$BATS_TEST_TMPDIR/sudo-unlocked"
  export PATH="$FIXTURES/bin/op-unlocked:$FIXTURES/bin/sudo-fake:$PATH"
  if is_macos; then xcode-select -p >/dev/null 2>&1 && [ -x /opt/homebrew/bin/brew ] || skip "prerequisites missing here; this test must not install them"
  else command -v git >/dev/null && command -v curl >/dev/null && [ -e /etc/ssl/certs/ca-certificates.crt ] || skip "prerequisites missing here; this test must not install them"; fi
  mkdir -p "$HOME/.local/bin"
  cp "$FIXTURES/bin/mise-log/mise" "$HOME/.local/bin/mise"
  export FAKE_MISE_VERSION; FAKE_MISE_VERSION=$(sed -n 's/^MISE_PIN="\${MISE_VERSION:-v\([^}]*\)}"$/\1/p' "$REPO_ROOT/bootstrap.sh")
  # The stub migration logs its arguments; FAKE_MIGRATE_DRY_EXIT makes its dry run report a conflict.
  cat > "$CO/tasks/migrate" <<'STUB'
#!/bin/sh
echo "migrate $*" >> "$CALL_LOG"
case " $* " in *" --dry-run "*) echo "migrate: dry run: nothing written"; exit "${FAKE_MIGRATE_DRY_EXIT:-0}" ;; esac
exit 0
STUB
  chmod +x "$CO/tasks/migrate"
}

# The Stow layout this Mac has: relative links into ~/.dotfiles, and a directory Stow folded.
stow_home() {
  local stow=${1:-$HOME/.dotfiles} rel=${2:-.dotfiles}
  mkdir -p "$stow/zsh" "$stow/ghostty/.config/ghostty" "$HOME/.config"
  echo '# old' > "$stow/zsh/.zshrc"
  ln -s "$rel/zsh/.zshrc" "$HOME/.zshrc"
  ln -s "../$rel/ghostty/.config/ghostty" "$HOME/.config/ghostty"
}
run_bootstrap() { "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop --machine studio --yes "$@"; }
line_of() { grep -n -m1 -e "$1" "$CALL_LOG" | cut -d: -f1; }

@test "a Stow-managed home is previewed, dry-run, migrated, then converged, in that order" {
  stow_home
  run run_bootstrap
  [ "$status" -eq 0 ]
  [ -n "$(line_of '^mise run remove-packages --dry-run')" ]
  [ -n "$(line_of '^migrate .*--dry-run')" ]
  [ -n "$(line_of "^migrate --checkout $CO --stow-dir $HOME/.dotfiles --yes\$")" ]
  [ -n "$(line_of '^mise bootstrap ')" ]
  [ "$(line_of '^mise run remove-packages --dry-run')" -lt "$(line_of '^migrate .*--dry-run')" ]
  [ "$(line_of '^migrate .*--dry-run')" -lt "$(line_of "^migrate --checkout $CO --stow-dir $HOME/.dotfiles --yes\$")" ]
  [ "$(line_of "^migrate --checkout $CO --stow-dir $HOME/.dotfiles --yes\$")" -lt "$(line_of '^mise bootstrap ')" ]
  [ -n "$(line_of '^mise run doctor')" ]
  [[ "$output" == *"migrated from $HOME/.dotfiles"* ]] || false
}

@test "once migrated, later runs converge without migrating again" {
  stow_home
  run run_bootstrap
  [ "$status" -eq 0 ]
  : > "$CALL_LOG"
  run run_bootstrap
  [ "$status" -eq 0 ]
  ! grep -q '^migrate' "$CALL_LOG" || false
  [ -n "$(line_of '^mise bootstrap ')" ]
}

@test "a home with no links into the Stow dir is never migrated" {
  mkdir -p "$HOME/.dotfiles/zsh" && echo '# unrelated' > "$HOME/.zshrc"
  run run_bootstrap
  [ "$status" -eq 0 ]
  ! grep -q -e '^migrate' -e '^mise run remove-packages' "$CALL_LOG" || false
  [ -n "$(line_of '^mise bootstrap ')" ]
}

@test "a conflict in the migration's dry run stops the run before anything is migrated or converged" {
  stow_home
  FAKE_MIGRATE_DRY_EXIT=1 run run_bootstrap
  [ "$status" -eq 1 ]
  [[ "$output" == *"tasks/migrate"*"--force"* ]] || false
  [ "$(grep -c '^migrate' "$CALL_LOG")" -eq 1 ]
  ! grep -q '^mise bootstrap ' "$CALL_LOG" || false
}

@test "--dry-run shows the removal list and the migration's dry run, and migrates nothing" {
  stow_home
  run run_bootstrap --dry-run
  [ "$status" -eq 0 ]
  [ -n "$(line_of '^migrate .*--dry-run')" ]
  [ "$(grep -c '^migrate' "$CALL_LOG")" -eq 1 ]
  [ -n "$(line_of '^mise bootstrap --dry-run')" ]
}

@test "--stow-dir takes over a Stow dir kept somewhere else" {
  stow_home "$HOME/src/dotfiles" src/dotfiles
  run run_bootstrap --stow-dir "$HOME/src/dotfiles"
  [ "$status" -eq 0 ]
  [ -n "$(line_of "^migrate --checkout $CO --stow-dir $HOME/src/dotfiles --yes\$")" ]
}
