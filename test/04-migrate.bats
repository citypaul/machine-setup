#!/usr/bin/env bats
# Gate 7: the journaled Stow-to-mise migration rolls back exactly after a partial failure.
# Fresh HOME with a Stow-style layout; the new checkout is a private copy; prerequisites skipped.
load helpers

setup() {
  require_jq
  require_mise
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  select_envs "$CO" personal desktop studio >/dev/null
  STOW="$HOME/.dotfiles"
  mkdir -p "$STOW/zsh"
  local f
  for f in .zshrc .zsh_profile .nvm_setup .pyenv_setup.sh; do
    printf '# old %s\n' "$f" > "$STOW/zsh/$f"
    ln -s ".dotfiles/zsh/$f" "$HOME/$f"      # relative links, as GNU Stow creates them
  done
  mkdir -p "$HOME/.config" && printf 'keep = me\n' > "$HOME/.config/unrelated.conf"
  MIGRATE=("$REPO_ROOT/tasks/migrate" --checkout "$CO" --stow-dir "$STOW" --skip-prerequisites --yes)
}

latest_journal() { ls -d "$HOME/.local/state/machine-setup/migration/"*/ | tail -1; }

@test "replaces Stow links with links into the new checkout, applies the new groups, and writes a manifest" {
  run "${MIGRATE[@]}"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.zshrc")" = "$CO/zsh/.zshrc" ]
  [ "$(readlink "$HOME/.zsh_profile")" = "$CO/zsh/.zsh_profile" ]
  [ "$(readlink "$HOME/.config/ghostty/config")" = "$CO/ghostty/.config/ghostty/config" ]
  [ "$(readlink "$HOME/.config/mise/conf.d/machine-setup.toml")" = "$CO/mise/.config/mise/conf.d/machine-setup.toml" ]
  [ ! -e "$HOME/.nvm_setup" ]   # declared absent: the old Stow link is removed
  grep -q 'name = Paul Hammond' "$HOME/.gitconfig"   # rendered from the git group's template
  [ ! -e "$HOME/.local/share/mise/installs" ]   # hooks run tasks; they must not pull every declared tool into HOME (F-35)
  [ "$(cat "$HOME/.config/unrelated.conf")" = "keep = me" ]
  [ -f "$(latest_journal)/manifest.before" ]
  [ -f "$(latest_journal)/journal.log" ]
  run bash -c "cd '$CO' && '$(mise_bin)' dot status --missing"
  [ "$status" -eq 0 ]
}

@test "failure after three replacement writes restores the pre-migration tree exactly" {
  local before; before=$(snapshot_tree "$HOME")
  MACHINE_SETUP_MIGRATE_FAIL_AFTER_WRITES=3 run "${MIGRATE[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rolled back"* ]]
  [ "$(snapshot_tree "$HOME")" = "$before" ]
}

@test "failure during verification restores the pre-migration tree exactly" {
  local before; before=$(snapshot_tree "$HOME")
  MACHINE_SETUP_MIGRATE_FAIL_AT=verify run "${MIGRATE[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rolled back"* ]]
  [ "$(snapshot_tree "$HOME")" = "$before" ]
}

@test "a real file at a target is reported as a conflict and nothing changes without --force" {
  rm "$HOME/.zsh_profile"; printf 'edited locally\n' > "$HOME/.zsh_profile"
  local before; before=$(snapshot_tree "$HOME")
  run "${MIGRATE[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *".zsh_profile"* ]]
  [ "$(snapshot_tree "$HOME")" = "$before" ]
}

@test "with --force a conflicting real file is saved in the journal before it is replaced" {
  rm "$HOME/.zsh_profile"; printf 'edited locally\n' > "$HOME/.zsh_profile"
  run "${MIGRATE[@]}" --force
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.zsh_profile")" = "$CO/zsh/.zsh_profile" ]
  grep -rq 'edited locally' "$(latest_journal)/saved"
}

@test "an existing real ~/.gitconfig is a conflict for the rendered template: refused without --force, saved with it" {
  printf '[user]\n\tname = unrelated\n' > "$HOME/.gitconfig"
  local before; before=$(snapshot_tree "$HOME")
  run "${MIGRATE[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *".gitconfig"* ]]
  [ "$(snapshot_tree "$HOME")" = "$before" ]
  run "${MIGRATE[@]}" --force
  [ "$status" -eq 0 ]
  grep -q 'name = Paul Hammond' "$HOME/.gitconfig"
  grep -rq 'name = unrelated' "$(latest_journal)/saved"
}
