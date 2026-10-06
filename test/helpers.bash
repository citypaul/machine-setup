# Shared helpers for the machine-setup bats suite. Sourced by every test file via `load helpers`.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export REPO_ROOT
FIXTURES="$REPO_ROOT/test/fixtures"

mise_bin() {
  if [ -n "${MISE_BIN:-}" ]; then printf '%s\n' "$MISE_BIN"; return 0; fi
  if command -v mise >/dev/null 2>&1; then command -v mise; return 0; fi
  if [ -x "$HOME/.local/bin/mise" ]; then printf '%s\n' "$HOME/.local/bin/mise"; return 0; fi
  return 1
}
mise() { "$(mise_bin)" "$@"; }

is_macos() { [ "$(uname -s)" = Darwin ]; }
is_linux() { [ "$(uname -s)" = Linux ]; }
skip_unless_macos() { is_macos || skip "macOS only"; }
skip_unless_linux() { is_linux || skip "Linux only"; }

# Mutating tests change the machine they run on (packages, ~/.zshrc, Homebrew, /Applications).
# They never run on a workstation by accident.
require_mutation() {
  [ "${MACHINE_SETUP_ALLOW_MUTATION:-}" = 1 ] || skip "set MACHINE_SETUP_ALLOW_MUTATION=1 on a disposable machine (CI runner or VM)"
}
require_mise() { mise_bin >/dev/null 2>&1 || skip "mise not installed; bootstrap installs it (set MISE_BIN for local runs)"; }

# A private copy of the checkout (tracked + untracked, minus ignored files) so a test can write
# the per-machine selection files without dirtying the real checkout.
copy_checkout() {
  local dest="$1"
  mkdir -p "$dest"
  if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    (cd "$REPO_ROOT" && git ls-files -co --exclude-standard -z | tar cf - --null -T -) | tar xf - -C "$dest"
  else
    (cd "$REPO_ROOT" && tar cf - --exclude=.git --exclude=.cache --exclude=.miserc.local.toml --exclude=mise.local.toml .) | tar xf - -C "$dest"
  fi
}

# A fresh HOME for tests that exercise dotfile mechanics without touching the real home.
fresh_home() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset MISE_ENV
  export MISE_YES=1
}

# Record the selection the way bootstrap.sh does, without running mise.
# select_envs <checkout> <profile> <roles,csv|-> <machine>
select_envs() {
  local roles=()
  [ "$3" != "-" ] && roles=(--role "$3")
  "$REPO_ROOT/bootstrap.sh" --dir "$1" --profile "$2" "${roles[@]}" --machine "$4" --select-only --yes
}

# Snapshot a tree as "path type detail mode" lines, excluding state/cache dirs mise and the
# migration journal write to. Used to prove a rollback restored a home directory exactly.
snapshot_tree() {
  local root="$1"
  (cd "$root" && find . -mindepth 1 \( -path ./.local -o -path ./.cache -o -path ./.config/mise \) -prune -o -print | sort | while IFS= read -r p; do
    if [ -L "$p" ]; then printf '%s link %s\n' "$p" "$(readlink "$p")"
    elif [ -d "$p" ]; then printf '%s dir -\n' "$p"
    else printf '%s file %s %s\n' "$p" "$(cksum < "$p" | cut -d' ' -f1)" "$(stat -f '%Lp' "$p" 2>/dev/null || stat -c '%a' "$p")"
    fi
  done)
}

# Where bootstrap keeps the per-machine selection inside a checkout.
env_list_of() { sed -n 's/^env = \[\(.*\)\]$/\1/p' "$1/.miserc.local.toml" | tr -d '" ' ; }
