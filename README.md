# machine-setup

One command turns a Mac or a Linux box with nothing on it into Paul's working
machine: packages, dotfiles, runtimes, identity, AI tooling. The same command,
run again, repairs whatever drifted. A `--profile` decides whether it is a
personal or a work machine, `--role` flags add optional sets (a desktop, a
Conquer network member), and `--machine` names the machine so it can carry its
own exceptions.

After that first run, use the `machine-setup` command it installs: `machine-setup
update` upgrades the computer, `machine-setup self-update` updates machine-setup
itself, and both work from any directory. See [Day to day](#day-to-day).

Under the hood it is one tool, [mise](https://mise.jdx.dev) and its
`bootstrap` command, plus a handful of small shell tasks for the things mise
does not do (package removal, a JSON merge, a journaled migration). That choice
was made by an executed spike against the risks a two-round review raised;
the evidence is in [ADR 0001](docs/adr/0001-orchestrator.md).

**Status:** in use. Slices 0 to 9 of [the plan](docs/planning/plan.md#5-slices)
are on `main`. Paul's MacBook Pro, a long-lived Mac that GNU Stow and Ansible
used to manage, was taken over on 2026-11-21 and runs from `main`. On
2026-11-22 the one-line install passed on a clean Ubuntu VM and a clean macOS
VM, each in one run from a clean snapshot, with the whole test suite green
afterwards (ADR 0001 E-29). CI runs the suite on a clean Ubuntu container and
a macOS runner for every pull request. What it does not cover is listed in
[What it does not do yet](#what-it-does-not-do-yet); read
[Taking over a machine that Stow manages](#taking-over-a-machine-that-stow-manages)
before running it on a Mac you already use.

## Contents

- [Set up a machine](#set-up-a-machine)
- [Day to day](#day-to-day)
- [Antigravity desktop and CLI](#antigravity-desktop-and-cli)
- [How a machine is described](#how-a-machine-is-described)
- [Dotfiles](#dotfiles)
- [Secrets and 1Password](#secrets-and-1password)
- [Tests](#tests)
- [Trying it on a VM](#trying-it-on-a-vm)
- [What it does not do yet](#what-it-does-not-do-yet)
- [Where things live](#where-things-live)

## Set up a machine

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
[Day to day](#day-to-day).

Flags:

| Flag | Meaning | Default |
|------|---------|---------|
| `--profile personal\|work` | which apps and configs load; personal-only apps never appear on a work machine | required the first time |
| `--role <name>` | additive set; repeat the flag or separate with commas (`desktop`, `conquer`) | none |
| `--machine <id>` | explicit machine id; loads `mise/config.machine-<id>.toml` if it exists | required the first time |
| `--os-family <family>` | Linux only: override the detected family for an odd derivative (supported: `debian`) | detected |
| `--git-email <addr>` | git `user.email` on this machine; saved, so later runs keep it; `--git-email ''` goes back to the default | `paul.hammond@gmail.com` |
| `--dir <checkout>` | use this checkout instead of cloning | `~/.local/share/machine-setup` |
| `--repo <url>`, `--ref <ref>` | where to clone from and what to check out | this repo, `main` |
| `--skip-system-update` | on a first install, do not update the system's own packages first (also `MACHINE_SETUP_SKIP_SYSTEM_UPDATE=1`; any value but `0` or `1` is refused) | off |
| `--stow-dir <dir>` | the GNU Stow dir an existing home links into; taken over once (see [Taking over a machine that Stow manages](#taking-over-a-machine-that-stow-manages)) | `~/.dotfiles` |
| `--select-only` | save the selection and stop; installs nothing | off |
| `--dry-run` | show what mise would do and stop | off |
| `--yes` | never ask a question; fail instead (sudo still asks for your password once, when it needs one) | off (prompts only on a terminal) |

Exit codes: `0` done, `2` a flag or this machine is not supported (nothing was
changed), `1` a step failed (earlier steps stay applied; fix and re-run).

## Day to day

Use `machine-setup`. The first install links it into `~/.local/bin` on every
machine, and it works from any directory: it finds the checkout by itself.

```bash
machine-setup update --dry-run    # what would an upgrade of this computer change?
machine-setup update --yes        # upgrade it
machine-setup self-update         # get the newest machine-setup ...
machine-setup converge            # ... and apply it to this machine
machine-setup check               # is this machine what the repo declares?
```

| Command | What it does | Flags |
|---------|--------------|-------|
| `machine-setup update` | Upgrades this computer on purpose: the system's own packages (apt and snaps; Homebrew and Apple's updates, never a restart), then the declared packages and tools. Nothing else ever upgrades. | `--dry-run` shows the plan and changes nothing; `--yes` applies it without asking. With neither, it shows the plan and asks. |
| `machine-setup self-update` | Updates machine-setup itself: fast-forwards the checkout to the newest commit of its branch, and lists what arrived. The command is a file in that checkout, so this updates the command too. It changes nothing else on the computer. | `--dry-run` lists what would arrive. |
| `machine-setup converge` | Applies the repo to this machine: installs what is declared and missing, repairs what drifted, runs the removal allowlist. Upgrades nothing. Asks for your sudo password once, when it needs it. | `--dry-run` previews; other flags are passed to `bootstrap.sh`. |
| `machine-setup check` | Checks this machine against the repo: selection, drift, the pinned mise, login shell, 1Password, Conquer, GPG card, skills pin, a cask image an interrupted converge left attached, Homebrew packages installed by hand that no layer declares. | none |
| `machine-setup help`, `--version` | The commands and exit codes; the commit and the checkout the command runs from. | |

Exit codes: `0` done; `1` the command ran and failed, or `check` found
something to fix; `2` an unknown command or flag.

Two things to know:

- **`update` and `self-update` are different.** `update` changes the computer's
  packages and leaves the repo alone. `self-update` changes the repo checkout
  and leaves the computer alone; run `machine-setup converge` afterwards to
  apply what arrived.
- **`self-update` only fast-forwards.** If the checkout has commits or edits
  of its own it stops, changes nothing, and prints the `git status` command to
  look at them.

### Less common commands

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

The saved selection lives in two untracked files in the checkout:
`.miserc.local.toml` (the list of config environments) and `mise.local.toml`
(profile, roles, machine, and `dotfiles.root`). Re-running with a flag changes
only that part of the selection; roles and machine are kept when you change
the profile.

## Antigravity desktop and CLI

Both profiles install the Antigravity CLI (`agy`) as a native mise tool on
macOS and Linux. On macOS, the `desktop` role also installs the
[Antigravity app](https://formulae.brew.sh/cask/antigravity) through mise's cask
manager in `/Applications/Antigravity.app`. Installing both requires macOS 13
or later.
The app manages agent conversations and projects visually; `agy` runs an agent
in the current project directory from your terminal. These are separate
packages from Antigravity IDE. See Google's [getting started guide](https://antigravity.google/docs/getting-started).

After this change is merged, update an existing setup and apply it:

```bash
machine-setup self-update
machine-setup converge --role desktop
```

To install just these two from an existing setup whose mise dotfiles are
already linked to a checkout containing this change:

```bash
cd ~/personal/machine-setup   # or the checkout printed by machine-setup --version
~/.local/bin/mise bootstrap packages apply brew-cask:antigravity --yes
~/.local/bin/mise install http:antigravity-cli
agy --version
open -a Antigravity
```

Sign in when prompted in the app. For the CLI, change to your project directory
and run `agy`, then complete its terminal setup, workspace trust and sign-in
prompts. Authentication stays on the machine; this repo supplies no credentials
or Antigravity settings.

Later, `machine-setup update` upgrades the desktop package and CLI tool through
mise. The CLI declaration discovers releases from Google's manifest, verifies
the download against its SHA-512 checksum, and exposes `agy` through mise's
PATH and shims. `AGY_CLI_DISABLE_AUTO_UPDATE=true` keeps CLI updates under mise;
use `machine-setup update` rather than `agy update`. The desktop app can also
update itself. Re-running converge installs missing packages and tools.

The CLI uses mise's HTTP backend because the pinned mise version installs the
CLI cask's wrapper without retaining the executable it launches. The release
feed includes Google's build id in the mise version. On Linux this installs
the CLI only; the desktop app is not managed here yet.

## How a machine is described

Everything is a mise config file in the repo root. Files load in this order,
and for the same key the later file wins:

| File | Loaded when | Holds |
|------|-------------|-------|
| `mise.toml` | always | dotfile groups, base packages, runtimes, tasks |
| `mise/config.macos.toml`, `mise/config.linux.toml` | automatically for the OS | casks and formulae, or apt packages |
| `mise/config.personal.toml`, `mise/config.work.toml` | `--profile` | personal-only apps; the work removal allowlist |
| `mise/config.desktop.toml`, `mise/config.conquer.toml`, `mise/config.appstore.toml` | each `--role` | the full dotfile-group list for that role; the Conquer join; App Store apps (opt in once signed in) |
| `mise/config.<role>-<os>.toml` | automatically with the role | OS-specific parts of a role: `mise/config.conquer-linux.toml` (apt repo, service), `mise/config.desktop-macos.toml` (Dock, iTerm2 profile), `mise/config.desktop-linux.toml` (the GUI set from the vendors' apt repositories, Ghostty, Obsidian, Docker) |
| `mise/config.machine-<id>.toml` | `--machine <id>` | this machine's full group list and exceptions: `personal-macbook` (Paul's MacBook Pro, its own Dock), `vm` (the two test VMs), `ci` (the runners) |

Two rules that are not obvious:

- **Dotfile-group lists replace, they do not merge.** A role or machine file
  that wants `ghostty` as well as `zsh` says `["zsh", "ghostty"]`, not
  `["ghostty"]`. A test checks that every machine file still yields `zsh`.
- **Removal is an explicit allowlist, never a prune.** Each layer contributes
  its own variable (`remove_cask_profile`, `remove_apt_machine`, and so on)
  and the `remove-packages` task joins them. Software you installed by hand
  is never touched.

## Dotfiles

A dotfile group is a folder laid out like your home directory, the same shape
as a GNU Stow package: `dotfiles/zsh/.zshrc`, `dotfiles/ghostty/.config/ghostty/config`. mise
links every file in a selected group into `$HOME` (`symlink-each`), so editing
`~/.zshrc` edits the file in the checkout and `git pull` updates every linked
file at once.

| Group | Deployed when | Notes |
|-------|---------------|-------|
| `zsh` | always | `.zshenv` puts mise's shims first for non-interactive shells, `.zprofile` keeps them first after macOS `path_helper`, `.zshrc` activates mise interactively; `claude-profile NAME` and `claude-personal` run Claude Code with a separate config directory per profile (opt-in; the machine default goes in `~/.zshrc.local`) |
| `rex` | `desktop` role, `personal-macbook` and `vm` machines | the primary terminal's `~/.config/rex/init.lua`; it binds nothing, so Rex keeps its default key bindings |
| `bin` | always | commands linked into `~/.local/bin`: `machine-setup` (see [Day to day](#day-to-day)) and `gpg-auto-sign`, the YubiKey-aware signing wrapper |
| `ghostty` | `desktop` role, `personal-macbook` machine | both the XDG and the Library config paths |
| `dotfiles/claude/settings.json` | always, but not linked | merged into `~/.claude/settings.json` by `tasks/merge-claude-settings`, keeping hooks you or herdr added |

[Rex](https://www.superlogical.com/rex) is the primary terminal. Its `init.lua`
binds nothing on purpose, so Rex's default key bindings always win; the tmux,
Zellij, Alacritty and Ghostty groups are still deployed but are not carried
into Rex. Rex is a beta with no Homebrew cask or public download, so nothing
here installs the app: install it by hand into `~/Applications`. For the same
reason it is not pinned in the Dock, where every listed app must already
exist. Theme and font live in Rex's Settings window, not in `init.lua`. After
editing the file, run `rex config check`, then `rex config reload`.

### Taking over a machine that Stow manages

The same command takes over a machine whose dotfiles are GNU Stow links into
`~/.dotfiles`, such as Paul's MacBook Pro:

```bash
cd ~/personal/machine-setup && git pull
./bootstrap.sh --dir "$PWD" --profile personal --role desktop --machine personal-macbook --dry-run   # see everything first; changes nothing
./bootstrap.sh --dir "$PWD" --profile personal --role desktop --machine personal-macbook             # do it; asks once before migrating
```

When a top-level dotfile or an entry in `~/.config` links into the Stow dir,
bootstrap, before it converges:

1. Lists the packages the removal allowlist would remove from this machine.
2. Runs the migration's dry run (`tasks/migrate --dry-run`). A real file where
   a link should go stops the run here, with nothing changed; the message
   gives the `tasks/migrate --force` command that saves the file in the
   journal and replaces it.
3. Asks once at a terminal (`--yes` skips the question), then migrates. Every
   write is journaled under `~/.local/state/machine-setup/migration/`, and any
   failure part-way rolls the home directory back exactly.
4. Converges as usual, then runs `check-machine`.

Before you start on a Mac you already use (learned taking over the MacBook
Pro, ADR 0001 F-64):

- **Back up.** The dotfile migration rolls back; the converge after it
  (packages, the Dock, the Claude settings merge) does not.
- **Carry over what the repo's files replace.** Move your own hosts from
  `~/.ssh/config` into `~/.ssh/config.d/` (any file name), your machine's git
  settings (signing key, `git-lfs` filters, extra aliases) into
  `~/.gitconfig.local`, and your own shell lines into `~/.zshrc.local`. The
  repo's files include all three and never write to them.
- **Delete an App Store copy of Slack**: the desktop role installs the cask.
- **Decide about the system update.** A first install upgrades every Homebrew
  package and runs Apple's updates. To skip that on a Mac that is already in
  use, pass `--skip-system-update`, and afterwards write the marker by hand so
  a later converge does not run it either:
  `date -u +%FT%TZ > ~/.local/state/machine-setup/system-updated`.
- **Run the `--dry-run` first.** It lists every real file that sits where the
  repo wants a link or a rendered file. `tasks/migrate --force` saves those in
  the journal and replaces them; run bootstrap again afterwards.

On macOS, allow the terminal to read the Desktop folder if asked: the
migration waits for that answer (ADR 0001 F-47). It runs once; later runs only
converge. `~/.dotfiles` is not touched, so remove it once you are happy.
`--stow-dir` names a Stow dir kept somewhere else.

### Rehearsing the migration on a VM

Run this on the macOS VM before touching a real Mac. Snapshot the VM after
step 2 so the rehearsal can be repeated. Steps 1 and 2 recreate the old
setup the way it is on Paul's Mac: Oh My Zsh as a real checkout, and only the
eight Stow packages that are live there, not everything `./install.sh` stows.

1. Install the Command Line Tools (a dialog opens; wait for it to finish),
   then Homebrew, then Stow and Oh My Zsh:

   ```bash
   xcode-select --install
   ```

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

   ```bash
   brew install stow && git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
   ```

2. Clone the old dotfiles and stow the live packages:

   ```bash
   git clone https://github.com/citypaul/.dotfiles ~/.dotfiles && cd ~/.dotfiles && stow zsh tmux gnupg alacritty zellij .oh-my-zsh ghostty herdr
   ```

3. Clone this repo to `~/machine-setup`, save the selection, and install the
   pinned mise (the selection step installs nothing):

   ```bash
   git clone https://github.com/citypaul/machine-setup ~/machine-setup
   ```

   ```bash
   cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --profile personal --role desktop --machine vm --select-only --yes
   ```

   ```bash
   curl -fsSL https://mise.run | MISE_VERSION=$(sed -n 's/^MISE_PIN="\(.*\)"$/\1/p' ~/machine-setup/bootstrap.sh) MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh
   ```

4. Dry run, then the migration, then a converge and `check-machine`:

   ```bash
   cd ~/machine-setup && tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles --dry-run
   ```

   ```bash
   cd ~/machine-setup && tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles
   ```

   ```bash
   cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --yes && ~/.local/bin/mise run check-machine
   ```

5. Restore the snapshot and rehearse a failure: the run must roll back and
   leave every file and link as it was.

   ```bash
   cd ~/machine-setup && MACHINE_SETUP_MIGRATE_FAIL_AT=verify tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles
   ```

## Secrets and 1Password

No secret is ever written to this repo, to a rendered file, to a dry run or to
a log. Tasks that need one (`tailscale-join`) read it from the 1Password CLI at
the moment they run and pass it straight to the process that needs it. When
`op whoami` fails, `bootstrap.sh` drops the roles that would need a secret
from the current run and tells you; run `op signin` and re-run to add them.

## Tests

The suite is [bats](https://github.com/bats-core/bats-core) files under
`test/`, one per gate or slice, run in name order. Files `00` to `09`, and
`11`, are safe anywhere: they use a fresh `HOME`, a private copy of the
checkout and stand-ins for `op`, `tailscale`, `sudo` and the package managers.
The other files from `10` to `95` change the machine they run on and refuse to
run unless `MACHINE_SETUP_ALLOW_MUTATION=1` is set.

| File | Proves |
|------|--------|
| `00-bootstrap-cli` | flag validation, OS detection, the saved selection |
| `00-bootstrap-migration` | a Stow-managed home is previewed, dry-run, migrated and converged in order, once; a conflict stops it before any change; a home without Stow links is left alone |
| `07-herdr-app` | the Herdr desktop app installs only with the desktop role, and a bad checksum or signature is refused |
| `01-layering` | group lists across profile, role and machine files; personal apps never reach work |
| `02-secrets` | a locked 1Password drops the Conquer role; the key is read at run time and never printed or stored |
| `03-merge-claude-settings` | the settings merge keeps foreign hooks, is idempotent and atomic |
| `04-migrate` | the Stow migration rolls back exactly after a failure mid-swap or during verification |
| `06-check-machine-update` | check-machine fails without a selection or mise, warns on a locked 1Password, reads the Conquer state, fails on drift; update shows its plan and applies nothing without --yes |
| `05-inventory` | every declared package names a manager this setup uses and exists in the Homebrew API; App Store ids live only in the opt-in role; the skills pin is an exact tag |
| `08-claude-profiles` | `claude-profile` and `claude-personal` give Claude Code the right config directory for one command, and change nothing otherwise |
| `09-system-update` | the system update: apt and snaps on Linux, Homebrew and Apple's updates on macOS, a restart-needing update only announced, failures and `--dry-run` |
| `10-bootstrap` | a real bootstrap: mise, packages, casks, pre-existing Homebrew apps left alone |
| `11-machine-setup-command` | `machine-setup` from another directory: `update`, `check` and `converge` run in the checkout with their flags and exit status; `self-update` fast-forwards the checkout, lists what arrived, and stops when it cannot; `--version`, help, and exit 2 for an unknown command or flag |
| `20-runtime-env` | node resolves in interactive, login and empty-environment shells |
| `30-drift` | a deleted dotfile or package is reported and repaired |
| `40-removal` | switching to `work` removes only the allowlisted personal apps |
| `50-ai-tooling` | skills at the pinned release, the settings merge on a real machine, herdr and OpenCode, the agent CLIs (`claude`, `codex`, `omp`) from mise |
| `60-conquer` | the role installs the Tailscale client and daemon; the join is a no-op when connected and prints the OIDC login URL when not |
| `70-identity` | git identity with the configurable email, private GPG files with this OS's pinentry and the public keys imported, the YubiKey-aware signing task, ssh config with the 1Password agent |
| `80-macos-extras` | Finder and keyboard preferences applied and current; with the desktop role the Dock order, the iTerm2 profile, the Alacritty theme, Rex's config, Talat |
| `95-check-machine-update` | check-machine passes on a converged machine; update --dry-run leaves it converged |
| `90-linux-desktop` | with the desktop role on Linux: 1Password, VS Code, Cursor and Brave from their vendors' repositories, Firefox, Alacritty, Ghostty, Docker with the user in its group, Obsidian as a Flatpak, no drift |

```bash
test/run.sh                                    # safe files run, mutating files skip
test/run.sh test/03-merge-claude-settings.bats # one file
MACHINE_SETUP_ALLOW_MUTATION=1 test/run.sh     # everything; VM or CI runner only
```

`test/run.sh` uses `bats` from `PATH` or fetches bats-core into `.cache/`.
The safe files need a mise binary: set `MISE_BIN=/path/to/mise` on a machine
where bootstrap has not installed one. GitHub Actions runs the whole suite in
an `ubuntu:24.04` container (as root, from nothing) and on a `macos-15`
runner (Homebrew already present) on every push and pull request.

## Trying it on a VM

The two VMPal VMs ("Ubuntu VM 1", "macOS VM 2") both mount the host's
`~/Downloads`. The working tree is mirrored to `~/Downloads/machine-setup`;
inside a VM, refresh the copy and work from it:

```bash
rsync -a --delete --exclude=.cache --exclude=.miserc.local.toml --exclude=mise.local.toml /media/VMPal/Downloads/machine-setup/ ~/machine-setup/   # Ubuntu
rsync -a --delete --exclude=.cache --exclude=.miserc.local.toml --exclude=mise.local.toml "/Volumes/My Shared Files/Downloads/machine-setup/" ~/machine-setup/   # macOS
```

Then, inside the VM:

```bash
cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --profile personal --role desktop --machine vm --yes       # first time
cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --yes                                                      # converge
cd ~/machine-setup && ~/.local/bin/mise bootstrap status --missing                                           # drift check
rm ~/.zshrc && cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --yes && ls -l ~/.zshrc                     # break, repair
cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --profile work --yes                                       # personal apps removed
cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --profile personal --yes                                   # and back
cd ~/machine-setup && MACHINE_SETUP_ALLOW_MUTATION=1 test/run.sh                                             # the whole suite
```

Long runs started by the agent are logged under `~/machine-setup/.cache/runs/`
in the VM; `tail -f` the newest file to watch one.

To rehearse a fresh machine, as ADR 0001 E-29 did: revert the VM to its clean
snapshot ("Clean + passwordless sudo 2026-11-04"), start it, and run the
one-line install from [Set up a machine](#set-up-a-machine) with `--machine
vm`. Then run the suite from `~/.local/share/machine-setup`, where the
one-liner puts the checkout. Two things about the snapshots: on the macOS one
sudo asks for a password, despite its name, and the full suite needs
passwordless sudo, so add it before running the tests; and the macOS VM may
need a second start after a revert, because the snapshot holds a suspended
session that a newer macOS cannot resume.

## What it does not do yet

Slices 0 to 9 of [the plan](docs/planning/plan.md#5-slices) are on `main`,
with CI green on both runners and the full suite green on both test VMs:
the package inventory and the personal/work split, the runtime contract,
the Conquer client, the AI tooling, identity, the macOS extras, the Linux
desktop set, machine files, `check-machine` and `update`. Still to come:

- the Conquer join against the real network: the role installs Tailscale and
  runs the OIDC login, but the Headscale URL is a placeholder until the
  details are settled (ADR 0001 D-23);
- a Mac that already has Slack from the App Store: the desktop role now
  installs Slack as a Homebrew cask (ADR 0001 D-38), so delete the App Store
  copy before the first converge there;
- the Dock on an Intel Mac: Talat is pinned and ships Apple Silicon builds
  only, so the Dock phase stops there until the list is changed (D-38);
- anything needing admin rights or extra permissions on a Mac: the
  automatic software-update check, the terminal's App Management
  permission and the Notification Center banner time (Full Disk Access)
  are not managed;
- Ghostty needs OpenGL 4.3; a VM whose virtual GPU offers less (the VMPal
  test VMs offer 4.1) closes it at once. The `vm` machine starts it with Mesa's
  software renderer instead (`LIBGL_ALWAYS_SOFTWARE=1`); real hardware keeps
  the GPU;
- on a Linux desktop: 1Password's desktop app exists for x86_64 only (arm64
  gets the CLI), and its SSH agent is switched on in the app's settings by
  hand; Google Chrome is not declared (Google publishes no Linux arm64
  build);
- moving an existing `~/.ssh/config` into `~/.ssh/config.d/` for you, and
  carrying over a machine's own git settings: both are done by hand before a
  takeover (see [Taking over a machine that Stow manages](#taking-over-a-machine-that-stow-manages));
- `--skip-system-update` leaves no marker, so the next converge without it
  runs the first-install update (ADR 0001 D-40); write the marker by hand on
  a machine you adopt;
- four apps on Paul's MacBook Pro that a rebuilt machine will not get, named
  in `unmanaged_cask` in `mise.toml`: `font-pt-mono` (its download answers
  401), `battle-net` and `steam` (mise cannot install them), `lazyworktree`
  (mise cannot read its tap) (F-68, D-43);
- `check-machine` cannot see that a cask needs a formula, so such a formula
  must be declared beside the cask, as `ghostscript` is for `mactex` (F-69);
- `mise run update` runs its own `apt-get update` without the retry
  bootstrap has for a lock held just after boot (F-66);
- the remaining Macs, and the rename of the public skills repo (slice 10).

## Where things live

| Path | What |
|------|------|
| `bootstrap.sh` | the first install and every converge; POSIX sh |
| `mise.toml`, `mise/config.*.toml`, `.miserc.toml` | the declared state, one file per layer |
| `dotfiles/<group>/` (`zsh`, `rex`, `ghostty`, `git`, `gnupg`, `ssh`, `bin`, `tmux`, `zellij`, `herdr`, `alacritty`, `mise`, `claude`) | dotfile groups and the Claude settings source |
| `dotfiles/bin/.local/bin/machine-setup` | the `machine-setup` command, linked into `~/.local/bin` on every machine |
| `tasks/` | the shell tasks mise runs: `remove-packages`, `merge-claude-settings`, `migrate`, `tailscale-join` |
| `test/` | the bats suite and its fixtures |
| `docs/adr/0001-orchestrator.md` | the orchestrator decision, every finding, every executed result |
| `docs/planning/plan.md` | proposal v4, open decisions, the review ledger, the slices |

## Licence

MIT. See [LICENSE](LICENSE).
