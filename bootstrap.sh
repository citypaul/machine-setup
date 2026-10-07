#!/bin/sh
# machine-setup bootstrap: one command sets up this machine, and the same command converges it later.
#
#   u=https://raw.githubusercontent.com/citypaul/machine-setup/main/bootstrap.sh
#   sh -c "$(curl -fsSL $u 2>/dev/null || wget -qO- $u 2>/dev/null || echo 'echo could not download bootstrap.sh >&2; exit 1')" -- \
#       --profile personal --role desktop --machine studio
#   (curl on macOS, wget on a fresh Ubuntu desktop, which has no curl until this script installs it)
#
# Flags select config environments (plan.md §4.9): --profile personal|work, --role <r> (repeatable,
# additive), --machine <id>. The OS is detected; the Linux distro family comes from /etc/os-release,
# --os-family overrides it for odd derivatives. Re-running with no flags reuses the saved selection.
# POSIX sh on purpose: the one-liner runs under whatever /bin/sh the machine has.
set -eu

MISE_PIN="${MISE_VERSION:-v2026.10.3}"
REPO_URL_DEFAULT="https://github.com/citypaul/machine-setup.git"
CHECKOUT_DEFAULT="${XDG_DATA_HOME:-$HOME/.local/share}/machine-setup"
# Envs whose tasks read 1Password during bootstrap are listed in mise.toml as `secret_envs`; they are
# dropped from a run when op is not signed in (plan §4.3 step 5). Empty since D6 chose OIDC for Conquer.
SECRET_ENVS=''

log() { printf 'machine-setup: %s\n' "$*"; }
die() { printf 'machine-setup: error: %s\n' "$1" >&2; exit "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
usage: bootstrap.sh [--profile personal|work] [--role <role>]... [--machine <id>] [--os-family <family>]
                    [--git-email <addr>] [--dir <checkout>] [--repo <url>] [--ref <ref>]
                    [--select-only] [--dry-run] [--yes]

  --profile      personal or work; decides which apps and configs load
  --role         additive role, e.g. desktop, conquer (repeat the flag or separate with commas)
  --machine      explicit machine id; loads mise.machine-<id>.toml
  --os-family    Linux only: override the family read from /etc/os-release (supported: debian)
  --git-email    git user.email on this machine (saved; later runs keep it; '' resets to the default)
  --dir          use this existing checkout instead of cloning
  --repo/--ref   where to clone from and what to check out (default: main of the public repo)
  --select-only  write the per-machine selection and stop (no installs)
  --dry-run      show what mise would do and stop
  --yes          never prompt; fail instead of asking
USAGE
}

# ---------------------------------------------------------------- arguments
profile='' roles='' machine='' os_family_override='' checkout='' repo_url=$REPO_URL_DEFAULT ref=''
git_email='' git_email_set=0
select_only=0 dry_run=0 yes=0
add_roles() { roles="$roles $(printf '%s' "$1" | tr ',' ' ')"; }
need_value() { [ $# -ge 2 ] || die "$1 needs a value" 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) need_value "$@"; profile=$2; shift 2 ;;
    --profile=*) profile=${1#*=}; shift ;;
    --role) need_value "$@"; add_roles "$2"; shift 2 ;;
    --role=*) add_roles "${1#*=}"; shift ;;
    --machine) need_value "$@"; machine=$2; shift 2 ;;
    --machine=*) machine=${1#*=}; shift ;;
    --os-family) need_value "$@"; os_family_override=$2; shift 2 ;;
    --os-family=*) os_family_override=${1#*=}; shift ;;
    --git-email) need_value "$@"; git_email=$2; git_email_set=1; shift 2 ;;
    --git-email=*) git_email=${1#*=}; git_email_set=1; shift ;;
    --dir) need_value "$@"; checkout=$2; shift 2 ;;
    --dir=*) checkout=${1#*=}; shift ;;
    --repo) need_value "$@"; repo_url=$2; shift 2 ;;
    --ref) need_value "$@"; ref=$2; shift 2 ;;
    --select-only) select_only=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --yes|-y) yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" 2 ;;
  esac
done
roles=$(printf '%s' "$roles" | tr -s ' ' | sed 's/^ //; s/ $//')
case "$git_email" in *\"*) die "--git-email: a double quote cannot be stored in mise.local.toml" 2 ;; esac

# ---------------------------------------------------------------- detection
os=$(uname -s)
case "$os" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *) die "unsupported operating system: $os" 2 ;;
esac
arch=$(uname -m)
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x64 ;;
esac
family=
if [ "$os" = linux ]; then
  id='' id_like=''
  if [ -r /etc/os-release ]; then
    id=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')
    id_like=$(sed -n 's/^ID_LIKE=//p' /etc/os-release | tr -d '"')
  fi
  case " $id $id_like " in
    *" debian "*|*" ubuntu "*) family=debian ;;
    *" fedora "*|*" rhel "*|*" centos "*) family=rhel ;;
    *" arch "*) family=arch ;;
    *" suse "*|*" opensuse "*) family=suse ;;
    *) family=${id:-unknown} ;;
  esac
  [ -z "$os_family_override" ] || family=$os_family_override
  case "$family" in
    debian) ;;
    *) die "unsupported Linux family '$family' (only debian-family distributions are supported so far; pass --os-family debian for an odd derivative)" 2 ;;
  esac
else
  [ -z "$os_family_override" ] || die "--os-family only applies on Linux" 2
fi
log "os=$os${family:+ family=$family} arch=$arch"

# ---------------------------------------------------------------- validation
case "$profile" in
  ""|personal|work) ;;
  *) die "unknown profile '$profile' (expected personal or work)" 2 ;;
esac
for r in $roles; do
  case "$r" in
    *[!a-z0-9-]*) die "role names are lowercase words with dashes: '$r'" 2 ;;
  esac
done
case "$machine" in
  *[!a-zA-Z0-9-]*) die "machine ids are letters, digits and dashes: '$machine'" 2 ;;
esac

interactive=0
if [ -t 0 ] && [ "$yes" = 0 ]; then interactive=1; fi

# Run a command as root: directly when already root, otherwise through sudo (non-interactively
# unless a terminal is attached).
as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"
  elif [ "$interactive" = 1 ]; then sudo "$@"
  else sudo -n "$@" || die "sudo needs a password and no terminal is attached; run 'sudo -v' first, then re-run"
  fi
}

# ---------------------------------------------------------------- prerequisites (git, curl, CLT, Homebrew, mise)
install_prerequisites() {
  if [ "$os" = linux ]; then
    if ! have git || ! have curl || [ ! -e /etc/ssl/certs/ca-certificates.crt ]; then
      log "installing git, curl and CA certificates with apt"
      DEBIAN_FRONTEND=noninteractive as_root apt-get update -qq
      DEBIAN_FRONTEND=noninteractive as_root apt-get install -y -qq --no-install-recommends git curl ca-certificates
    fi
  else
    if ! xcode-select -p >/dev/null 2>&1; then
      log "installing the Xcode Command Line Tools"
      # Headless path first: ask softwareupdate for the CLT label (works with sudo and no GUI).
      touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      # The label is "Command Line Tools for Xcode-15.3" on older releases and
      # "Command Line Tools for Xcode 27.0-27.0" from macOS 27; match both, take the newest.
      label=$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools for Xcode.*\)$/\1/p' | sort | tail -1 || true)
      if [ -n "$label" ]; then as_root softwareupdate -i "$label" --verbose || true; fi
      rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      if ! xcode-select -p >/dev/null 2>&1; then
        xcode-select --install >/dev/null 2>&1 || true
        log "waiting for the Command Line Tools installer to finish (accept the dialog if one appeared)"
        while ! xcode-select -p >/dev/null 2>&1; do sleep 10; done
      fi
    fi
    if [ ! -x /opt/homebrew/bin/brew ]; then
      log "installing Homebrew (mise pours into the same prefix; brew stays available for uninstall and for you)"
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  fi
}

MISE="$HOME/.local/bin/mise"
install_mise() {
  want=${MISE_PIN#v}
  if [ -x "$MISE" ] && [ "$("$MISE" --version 2>/dev/null | cut -d' ' -f1)" = "$want" ]; then return 0; fi
  log "installing mise $MISE_PIN to $MISE"
  curl -fsSL https://mise.run | MISE_VERSION="$MISE_PIN" MISE_INSTALL_PATH="$MISE" sh >/dev/null
  "$MISE" --version >/dev/null
}

# ---------------------------------------------------------------- checkout
resolve_checkout() {
  if [ -n "$checkout" ]; then
    checkout=$(cd "$checkout" 2>/dev/null && pwd) || die "--dir $checkout does not exist" 2
    [ -f "$checkout/mise.toml" ] || die "$checkout is not a machine-setup checkout (no mise.toml)" 2
    return 0
  fi
  checkout=$CHECKOUT_DEFAULT
  if [ ! -d "$checkout/.git" ]; then
    log "cloning $repo_url into $checkout"
    mkdir -p "$(dirname "$checkout")"
    git clone --quiet "$repo_url" "$checkout"
    [ -z "$ref" ] || git -C "$checkout" checkout --quiet "$ref"
  fi
}

# ---------------------------------------------------------------- selection (saved in the checkout, never committed)
saved_var() { sed -n "s/^$1 = \"\(.*\)\"\$/\1/p" "$checkout/mise.local.toml" 2>/dev/null | head -1; }
load_saved_selection() {
  [ -n "$profile" ] || profile=$(saved_var profile)
  [ -n "$roles" ] || roles=$(saved_var roles)
  [ -n "$machine" ] || machine=$(saved_var machine)
  [ "$git_email_set" = 1 ] || git_email=$(saved_var git_email)
}
ask() { # ask <prompt>; the answer is left in $reply
  printf '%s: ' "$1"
  read -r reply
}
complete_selection() {
  if [ -z "$profile" ]; then
    [ "$interactive" = 1 ] || die "no saved selection and no --profile given (personal or work)" 2
    ask "Profile [personal/work]"; profile=$reply
    case "$profile" in personal|work) ;; *) die "unknown profile '$profile'" 2 ;; esac
  fi
  if [ -z "$machine" ]; then
    [ "$interactive" = 1 ] || die "no saved selection and no --machine given (an explicit id, e.g. studio)" 2
    ask "Machine id (e.g. studio)"; machine=$reply
    [ -n "$machine" ] || die "a machine id is required" 2
  fi
  if [ -z "$roles" ] && [ "$interactive" = 1 ] && [ -z "$(saved_var profile)" ]; then
    ask "Roles, space separated (e.g. desktop conquer), or empty"; roles=$reply
  fi
}

# Run a command with stdin, stdout and stderr only. The 1Password CLI leaves a daemon behind (on
# `op whoami`, and when its cask generates completions during `mise bootstrap`) that keeps every
# descriptor it inherited, so a caller waiting for EOF on one never finishes: bats keeps its output
# pipe on 3 and on copies above 9 (ADR 0001 F-41). Perl closes them all; dash cannot name fds above 9.
stdio_only() { perl -e 'use POSIX (); POSIX::close($_) for 3 .. 1023; exec { $ARGV[0] } @ARGV or die "stdio_only: cannot run $ARGV[0]: $!\n"' "$@"; }
# launchd starts macOS processes, Terminal's shells among them, with a soft limit of 256 open files;
# mise's npm installs open more and fail with "Too many open files" (ADR 0001 F-55). Raise the soft
# limit for this run to 10240, or to the hard limit when that is lower. Never lower it.
# shellcheck disable=SC3045  # ulimit -S/-H: not POSIX, but dash, bash, zsh and busybox sh have them;
# a shell without them skips the raise.
raise_open_files() {
  soft=$(ulimit -Sn 2>/dev/null) || return 0
  [ "$soft" = unlimited ] || [ "$soft" -ge 10240 ] || ulimit -Sn 10240 2>/dev/null || ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true
}
op_signed_in() { have op && stdio_only op whoami >/dev/null 2>&1; }
compute_envs() {
  envs=$profile
  skipped=
  for r in $roles; do
    case " $SECRET_ENVS " in
      *" $r "*)
        if op_signed_in; then envs="$envs,$r"; else skipped="$skipped $r"; fi ;;
      *) envs="$envs,$r" ;;
    esac
  done
  envs="$envs,machine-$machine"
  # Role and profile overlays per OS: mise.<env>-<os>.toml is selected right after <env> when the
  # checkout has it (OS-specific files, services and packages that belong to a role).
  expanded=''
  for e in $(printf '%s' "$envs" | tr ',' ' '); do
    expanded="$expanded,$e"
    [ -f "$checkout/mise.$e-$os.toml" ] && expanded="$expanded,$e-$os"
  done
  envs=${expanded#,}
  if [ -n "$skipped" ]; then
    log "1Password is not signed in (op whoami failed); skipping env(s):$skipped. Run 'op signin' and re-run bootstrap to add them."
  fi
}

write_selection() {
  env_toml=$(printf '%s' "$envs" | sed 's/,/", "/g; s/^/"/; s/$/"/')
  {
    echo "# Written by bootstrap.sh: this machine's config environments. Not tracked."
    echo "env = [$env_toml]"
  } > "$checkout/.miserc.local.toml"
  {
    echo "# Written by bootstrap.sh. Not tracked. Re-run bootstrap.sh with flags to change the selection."
    echo "[vars]"
    echo "profile = \"$profile\""
    echo "roles = \"$roles\""
    echo "machine = \"$machine\""
    # Per-machine override of the base git_email var (D-20); absent, the default in mise.toml applies.
    [ -z "$git_email" ] || echo "git_email = \"$git_email\""
    echo
    echo "[settings]"
    echo "dotfiles.root = \"$checkout\""
  } > "$checkout/mise.local.toml"
  log "selection saved in $checkout (profile=$profile roles='$roles' machine=$machine${git_email:+ git_email=$git_email})"
  log "envs=$envs"
}

# ---------------------------------------------------------------- main
if [ "$select_only" = 0 ]; then
  install_prerequisites
  install_mise
fi
resolve_checkout
SECRET_ENVS=$(sed -n 's/^secret_envs = "\(.*\)"$/\1/p' "$checkout/mise.toml" 2>/dev/null | head -1)
load_saved_selection
complete_selection
compute_envs
write_selection
[ "$select_only" = 0 ] || exit 0

cd "$checkout"   # .miserc files are read from the real cwd before -C applies (ADR 0001 F-07)
raise_open_files
# Hooks and tasks run `mise …` by name; a bare container or fresh account has no ~/.local/bin on PATH yet.
PATH="$HOME/.local/bin:$PATH"; export PATH
export MISE_YES=1
# Trust the checkout durably. `mise trust` records nothing when CI=true is set (mise auto-trusts
# in CI), and a later shell without that variable would then refuse the config (ADR 0001 F-18).
if ! "$MISE" settings get trusted_config_paths 2>/dev/null | grep -qF "\"$checkout\""; then
  "$MISE" settings add trusted_config_paths "$checkout" >/dev/null
fi
"$MISE" trust --quiet >/dev/null 2>&1 || true
if [ "$dry_run" = 1 ]; then
  "$MISE" bootstrap --dry-run
  exit 0
fi
log "converging with mise bootstrap"
# --update refreshes apt metadata so a repository added in this run (pre-packages files) is usable.
# Services need systemd as PID 1; in a container (CI, WSL1) mise refuses the change (ADR 0001 F-36).
if [ "$os" = linux ] && [ ! -d /run/systemd/system ]; then
  log "no systemd on this machine: declared services are installed but not enabled or started"
  set -- --skip services
else
  set --
fi
stdio_only "$MISE" bootstrap --update --yes "$@"
log "done. Log out and back in (or reboot) so every terminal and app starts with zsh, the new PATH and"
log "the new launchers; until then, run exec zsh in a terminal that is already open."
