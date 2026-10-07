# Shared helpers for the machine-setup bats suite. Sourced by every test file via `load helpers`.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export REPO_ROOT
FIXTURES="$REPO_ROOT/test/fixtures"

# The mise bootstrap installs, located with the real HOME: helpers load before setup, and fresh_home
# later points HOME at a test directory (on a fresh machine mise is not on PATH yet, so this lookup was
# the one that mattered, and it ran after HOME had moved).
bootstrap_mise="$HOME/.local/bin/mise"

# Path of the mise executable: $MISE_BIN, else one on PATH, else the one bootstrap installs.
# `type -P` looks only at executables, never at the `mise` shell function defined below.
mise_bin() {
  if [ -n "${MISE_BIN:-}" ]; then printf '%s\n' "$MISE_BIN"; return 0; fi
  local found
  if found=$(type -P mise 2>/dev/null) && [ -n "$found" ]; then printf '%s\n' "$found"; return 0; fi
  if [ -x "$bootstrap_mise" ]; then printf '%s\n' "$bootstrap_mise"; return 0; fi
  return 1
}
mise() { "$(mise_bin)" "$@"; }
# Pin that mise for everything the suite starts: tasks and bootstrap scripts honour MISE_BIN, and they
# run under a test HOME where ~/.local/bin/mise does not exist.
if [ -z "${MISE_BIN:-}" ] && found_mise=$(mise_bin); then export MISE_BIN="$found_mise"; fi

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
# jq is a dependency of the assertions themselves (and of two tasks); the CI harness installs it.
require_jq() { command -v jq >/dev/null 2>&1 || skip "jq not installed (test harness dependency)"; }

# A private copy of the checkout (tracked + untracked, minus ignored files) so a test can write
# the per-machine selection files without dirtying the real checkout.
copy_checkout() {
  local dest="$1"
  mkdir -p "$dest"
  # On a Mac without the Command Line Tools, `git` is a shim that only requests their install.
  if { [ "$(uname -s)" != Darwin ] || xcode-select -p >/dev/null 2>&1; } && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
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
    else printf '%s file %s %s\n' "$p" "$(cksum < "$p" | cut -d' ' -f1)" "$(file_mode "$p")"
    fi
  done)
}

# Octal permission bits of a file. GNU `stat -f` means *filesystem* status (and prints changing
# free-block counts), so the form is chosen by OS rather than by trying one and falling back.
file_mode() {
  if [ "$(uname -s)" = Darwin ]; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}

# Run the installed mise from the checkout, where the config and the saved selection live.
# Run a command with stdin, stdout and stderr only. A daemon it starts (op, gpg-agent) keeps every
# descriptor it inherits; bats keeps its output pipe on fd 3 and on copies above 9 that macOS's bash
# 3.2 leaves inheritable, and waits for EOF on it (ADR 0001 F-41).
stdio_only() { perl -e 'use POSIX (); POSIX::close($_) for 3 .. 1023; exec { $ARGV[0] } @ARGV or die "stdio_only: cannot run $ARGV[0]: $!\n"' "$@"; }
mise_in_checkout() { (cd "$REPO_ROOT" && stdio_only "$HOME/.local/bin/mise" "$@"); }
# True when mise reports nothing unconverged. When something is, mise's status table goes to the
# test's output, so a failing test names what was missing.
converged() {
  local table
  table=$(mise_in_checkout bootstrap status --missing 2>&1) && return 0
  printf '%s\n' "$table"
  return 1
}

# Where bootstrap keeps the per-machine selection inside a checkout.
env_list_of() { sed -n 's/^env = \[\(.*\)\]$/\1/p' "$1/.miserc.local.toml" | tr -d '" ' ; }
