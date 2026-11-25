# The first install and `bootstrap.sh`

[Back to the README](../README.md)

`bootstrap.sh` does the first install and every later converge. This page is
its reference: what a run does in order, every flag, the exit codes, where the
selection is saved, and the commands for less common jobs. For everyday use,
see `machine-setup` in the [README](../README.md#day-to-day).

## The one-line install

On a machine with nothing installed, not even git or the Xcode Command Line
Tools:

```bash
u=https://raw.githubusercontent.com/citypaul/machine-setup/main/bootstrap.sh; sh -c "$(curl -fsSL $u 2>/dev/null || wget -qO- $u 2>/dev/null || echo 'echo could not download bootstrap.sh >&2; exit 1')" -- --profile personal --role desktop --machine personal-macbook --yes
```

It downloads the script with `curl` (macOS) or `wget` (a fresh Ubuntu desktop
has no curl) and stops with an error if it cannot download either way.

What happens, in order:

1. Detects the OS and, on Linux, the distro family from `/etc/os-release`.
2. Unless you are root or have passwordless sudo, asks for your password
   once (sudo prompts, even with `--yes`) and keeps sudo unlocked until the
   run ends: several steps need root, and macOS forgets a password after
   five minutes.
3. Installs its own prerequisites: `git`, `curl` and CA certificates on
   Debian-family Linux; the Command Line Tools (headless, via
   `softwareupdate`) and Homebrew on macOS.
4. Installs a pinned mise to `~/.local/bin/mise`.
5. Clones this repo to `~/.local/share/machine-setup` and saves your
   selection there (profile, roles, machine id).
6. Checks whether 1Password's CLI is signed in; roles that need a secret at
   run time (`conquer`) are skipped for this run if it is not, and it says so.
7. On a first install only, updates the system's own packages before
   installing anything: `apt full-upgrade` and `snap refresh` on Ubuntu;
   Homebrew and Apple's `softwareupdate` on macOS. An Apple update that
   needs a restart is announced, never downloaded or installed for you.
   Later runs never upgrade; `machine-setup update` does it on purpose.
8. Runs `mise bootstrap`: system packages, Homebrew formulae and casks,
   dotfile links, the removal allowlist, runtimes, the Claude settings merge.
9. Asks you to log out and back in: a desktop session keeps the shell and
   PATH it started with, so terminals such as Ghostty and Alacritty, and
   launchers for new per-user apps, only pick up the change at the next login.

From then on the machine has the `machine-setup` command on its PATH; see
[Day to day](../README.md#day-to-day).

## Flags

| Flag | Meaning | Default |
|------|---------|---------|
| `--profile personal\|work` | which apps and configs load; personal-only apps never appear on a work machine | required the first time |
| `--role <name>` | additive set; repeat the flag or separate with commas (`desktop`, `conquer`) | none |
| `--machine <id>` | explicit machine id; loads `mise/config.machine-<id>.toml` if it exists | required the first time |
| `--os-family <family>` | Linux only: override the detected family for an odd derivative (supported: `debian`) | detected |
| `--git-email <addr>` | git `user.email` on this machine; saved, so later runs keep it; `--git-email ''` goes back to the default | `git_email` in `mise.toml` |
| `--dir <checkout>` | use this checkout instead of cloning | `~/.local/share/machine-setup` |
| `--repo <url>`, `--ref <ref>` | where to clone from and what to check out | this repo, `main` |
| `--skip-system-update` | on a first install, do not update the system's own packages first (also `MACHINE_SETUP_SKIP_SYSTEM_UPDATE=1`; any value but `0` or `1` is refused) | off |
| `--stow-dir <dir>` | the GNU Stow dir an existing home links into; taken over once (see [Taking over a machine that Stow manages](taking-over-a-machine.md)) | `~/.dotfiles` |
| `--select-only` | save the selection and stop; installs nothing | off |
| `--dry-run` | show what mise would do and stop | off |
| `--yes` | never ask a question; fail instead (sudo still asks for your password once, when it needs one) | off (prompts only on a terminal) |

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | done |
| `1` | a step failed; earlier steps stay applied, so fix the cause and run it again |
| `2` | a flag or this machine is not supported; nothing was changed |

## Where the selection is saved

The saved selection lives in two untracked files in the checkout:
`.miserc.local.toml` (the list of config environments) and `mise.local.toml`
(profile, roles, machine, and `dotfiles.root`). Re-running with a flag changes
only that part of the selection; roles and machine are kept when you change
the profile.

## Less common commands

These run from inside the checkout. After the one-liner that is
`~/.local/share/machine-setup`; on the test VMs it is `~/machine-setup`.
`machine-setup --version` prints the path.

```bash
cd ~/.local/share/machine-setup
```

| You want to | Run |
|-------------|-----|
| See whether anything drifted (exit `0` means no) | `~/.local/bin/mise bootstrap status --missing` |
| See the whole declared state | `~/.local/bin/mise bootstrap status` |
| Switch this machine to the work profile (personal apps are removed) | `./bootstrap.sh --profile work --yes` |
| Switch back | `./bootstrap.sh --profile personal --yes` |
| Add a role (for example after signing in to 1Password) | `./bootstrap.sh --role conquer --yes` |
| See what the removal allowlist would remove, without removing | `~/.local/bin/mise run remove-packages --dry-run` |
| Join the Conquer network by hand | `~/.local/bin/mise run tailscale-join` |
| See the git identity this machine renders | `git config --global user.email` |
| Use a different git email on this machine (later runs keep it; `''` goes back to the default) | `./bootstrap.sh --git-email you@example.com --yes` |
| Configure YubiKey signing (explains and exits 0 when no key is inserted) | `~/.local/bin/mise run gpg-setup` |
| See which macOS preferences differ from the declared ones | `~/.local/bin/mise bootstrap macos defaults status` |
| Install the gh extensions once `gh auth login` has run | `~/.local/bin/mise run gh-extensions` |
| Install Talat by hand (Apple Silicon, desktop role) | `~/.local/bin/mise run talat` |
| Install the Herdr desktop app by hand (desktop role; the `herdr` CLI comes with every profile) | `~/.local/bin/mise run herdr-app` |
| Install Ghostty on Ubuntu by hand (desktop role) | `~/.local/bin/mise run ghostty-linux` |
| Update only the system's own packages (apt and snaps; Homebrew and Apple's updates, never a restart) | `~/.local/bin/mise run system-update` |
