# machine-setup

One command turns a Mac or a Linux box with nothing on it into Paul's working
machine: packages, dotfiles, runtimes, identity, AI tooling. The same command,
run again, repairs whatever drifted. A `--profile` decides whether it is a
personal or a work machine, `--role` flags add optional sets (a desktop, a
Conquer network member), and `--machine` names the machine so it can carry its
own exceptions.

Under the hood it is one tool, [mise](https://mise.jdx.dev) and its
`bootstrap` command, plus a handful of small shell tasks for the things mise
does not do (package removal, a JSON merge, a journaled migration). That choice
was made by an executed spike against the risks a two-round review raised;
the evidence is in [ADR 0001](docs/adr/0001-orchestrator.md).

**Status:** slice 0 of 10 is done (the orchestrator decision and a walking
skeleton proven on a clean Ubuntu VM, a clean macOS VM and GitHub Actions).
It is not yet safe to run on a machine you care about: see
[What it does not do yet](#what-it-does-not-do-yet).

## Contents

- [Set up a machine](#set-up-a-machine)
- [Day to day](#day-to-day)
- [How a machine is described](#how-a-machine-is-described)
- [Dotfiles](#dotfiles)
- [Secrets and 1Password](#secrets-and-1password)
- [Tests](#tests)
- [Trying it on a VM](#trying-it-on-a-vm)
- [What it does not do yet](#what-it-does-not-do-yet)
- [Where things live](#where-things-live)

## Set up a machine

On a disposable machine (a VM or a CI runner), with nothing installed, not
even git or the Xcode Command Line Tools:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/citypaul/machine-setup/main/bootstrap.sh)" -- --profile personal --role desktop --machine studio --yes
```

What happens, in order:

1. Detects the OS and, on Linux, the distro family from `/etc/os-release`.
2. Installs its own prerequisites: `git`, `curl` and CA certificates on
   Debian-family Linux; the Command Line Tools (headless, via
   `softwareupdate`) and Homebrew on macOS.
3. Installs a pinned mise to `~/.local/bin/mise`.
4. Clones this repo to `~/.local/share/machine-setup` and saves your
   selection there (profile, roles, machine id).
5. Checks whether 1Password's CLI is signed in; roles that need a secret at
   run time (`conquer`) are skipped for this run if it is not, and it says so.
6. Runs `mise bootstrap`: system packages, Homebrew formulae and casks,
   dotfile links, the removal allowlist, runtimes, the Claude settings merge.

Flags:

| Flag | Meaning | Default |
|------|---------|---------|
| `--profile personal\|work` | which apps and configs load; personal-only apps never appear on a work machine | required the first time |
| `--role <name>` | additive set; repeat the flag or separate with commas (`desktop`, `conquer`) | none |
| `--machine <id>` | explicit machine id; loads `mise.machine-<id>.toml` if it exists | required the first time |
| `--os-family <family>` | Linux only: override the detected family for an odd derivative (supported: `debian`) | detected |
| `--git-email <addr>` | git `user.email` on this machine; saved, so later runs keep it; `--git-email ''` goes back to the default | `paul.hammond@gmail.com` |
| `--dir <checkout>` | use this checkout instead of cloning | `~/.local/share/machine-setup` |
| `--repo <url>`, `--ref <ref>` | where to clone from and what to check out | this repo, `main` |
| `--select-only` | save the selection and stop; installs nothing | off |
| `--dry-run` | show what mise would do and stop | off |
| `--yes` | never prompt; fail instead of asking | off (prompts only on a terminal) |

Exit codes: `0` done, `2` a flag or this machine is not supported (nothing was
changed), `1` a step failed (earlier steps stay applied; fix and re-run).

## Day to day

All of these run from inside the checkout. After the one-liner that is
`~/.local/share/machine-setup`; on the test VMs it is `~/machine-setup`.

```bash
cd ~/.local/share/machine-setup
```

| You want to | Run |
|-------------|-----|
| Converge: repair anything that drifted, upgrade nothing | `./bootstrap.sh --yes` |
| See whether anything drifted (exit `0` means no) | `~/.local/bin/mise bootstrap status --missing` |
| See the whole declared state | `~/.local/bin/mise bootstrap status` |
| Preview what a converge would change | `./bootstrap.sh --dry-run` |
| Switch this machine to the work profile (personal apps are removed) | `./bootstrap.sh --profile work --yes` |
| Switch back | `./bootstrap.sh --profile personal --yes` |
| Add a role (for example after signing in to 1Password) | `./bootstrap.sh --role conquer --yes` |
| Pick up new config from the repo, then converge | `git pull && ./bootstrap.sh --yes` |
| See what the removal allowlist would remove, without removing | `~/.local/bin/mise run remove-packages --dry-run` |
| Join the Conquer network by hand | `~/.local/bin/mise run tailscale-join` |
| See the git identity this machine renders | `git config --global user.email` |
| Use a different git email on this machine (later runs keep it; `''` goes back to the default) | `./bootstrap.sh --git-email you@example.com --yes` |
| Configure YubiKey signing (explains and exits 0 when no key is inserted) | `~/.local/bin/mise run gpg-setup` |
| See which macOS preferences differ from the declared ones | `~/.local/bin/mise bootstrap macos defaults status` |
| Install the gh extensions once `gh auth login` has run | `~/.local/bin/mise run gh-extensions` |
| Install Talat by hand (Apple Silicon, desktop role) | `~/.local/bin/mise run talat` |
| Install Ghostty on Ubuntu by hand (desktop role) | `~/.local/bin/mise run ghostty-linux` |
| Check what mise cannot: selection, drift, login shell, 1Password, Conquer, GPG card, skills pin | `~/.local/bin/mise run doctor` (exit `1` when something needs running) |
| See what an upgrade would do | `~/.local/bin/mise run update -- --dry-run` |
| Upgrade declared packages and tools on purpose | `~/.local/bin/mise run update -- --yes` |

The saved selection lives in two untracked files in the checkout:
`.miserc.local.toml` (the list of config environments) and `mise.local.toml`
(profile, roles, machine, and `dotfiles.root`). Re-running with a flag changes
only that part of the selection; roles and machine are kept when you change
the profile.

## How a machine is described

Everything is a mise config file in the repo root. Files load in this order,
and for the same key the later file wins:

| File | Loaded when | Holds |
|------|-------------|-------|
| `mise.toml` | always | dotfile groups, base packages, runtimes, tasks |
| `mise.macos.toml`, `mise.linux.toml` | automatically for the OS | casks and formulae, or apt packages |
| `mise.personal.toml`, `mise.work.toml` | `--profile` | personal-only apps; the work removal allowlist |
| `mise.desktop.toml`, `mise.conquer.toml`, `mise.appstore.toml` | each `--role` | the full dotfile-group list for that role; the Conquer join; App Store apps (opt in once signed in) |
| `mise.<role>-<os>.toml` | automatically with the role | OS-specific parts of a role: `mise.conquer-linux.toml` (apt repo, service), `mise.desktop-macos.toml` (Dock, iTerm2 profile), `mise.desktop-linux.toml` (the GUI set from the vendors' apt repositories, Ghostty, Obsidian, Docker) |
| `mise.machine-<id>.toml` | `--machine <id>` | this machine's full group list and exceptions: `studio` (Paul's Mac Studio, its own Dock), `vm` (the two test VMs), `ci` (the runners) |

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
as a GNU Stow package: `zsh/.zshrc`, `ghostty/.config/ghostty/config`. mise
links every file in a selected group into `$HOME` (`symlink-each`), so editing
`~/.zshrc` edits the file in the checkout and `git pull` updates every linked
file at once.

| Group | Deployed when | Notes |
|-------|---------------|-------|
| `zsh` | always | `.zshenv` puts mise's shims first for non-interactive shells, `.zprofile` keeps them first after macOS `path_helper`, `.zshrc` activates mise interactively |
| `ghostty` | `desktop` role, `studio` machine | both the XDG and the Library config paths |
| `claude/settings.json` | always, but not linked | merged into `~/.claude/settings.json` by `tasks/merge-claude-settings`, keeping hooks you or herdr added |

Moving an existing Stow-managed machine over is a separate, journaled
operation that rolls back exactly if anything fails part-way:

```bash
tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles --dry-run   # see what would change
tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles             # do it; originals saved under ~/.local/state/machine-setup/migration/
```

A real file where a link should go stops the migration; `--force` saves it in
the journal first and then replaces it.

## Secrets and 1Password

No secret is ever written to this repo, to a rendered file, to a dry run or to
a log. Tasks that need one (`tailscale-join`) read it from the 1Password CLI at
the moment they run and pass it straight to the process that needs it. When
`op whoami` fails, `bootstrap.sh` drops the roles that would need a secret
from the current run and tells you; run `op signin` and re-run to add them.

## Tests

The suite is [bats](https://github.com/bats-core/bats-core) files under
`test/`, one per gate or slice, run in name order. Files `00` to `05` are
safe anywhere: they use a fresh `HOME`, a private copy of the checkout and
fake `op` and `tailscale` binaries. Files `10` to `95` change the machine
they run on and refuse to run unless `MACHINE_SETUP_ALLOW_MUTATION=1` is set.

| File | Proves |
|------|--------|
| `00-bootstrap-cli` | flag validation, OS detection, the saved selection |
| `01-layering` | group lists across profile, role and machine files; personal apps never reach work |
| `02-secrets` | a locked 1Password drops the Conquer role; the key is read at run time and never printed or stored |
| `03-merge-claude-settings` | the settings merge keeps foreign hooks, is idempotent and atomic |
| `04-migrate` | the Stow migration rolls back exactly after a failure mid-swap or during verification |
| `06-doctor-update` | doctor fails without a selection or mise, warns on a locked 1Password, reads the Conquer state, fails on drift; update shows its plan and applies nothing without --yes |
| `05-inventory` | every declared package names a manager this setup uses and exists in the Homebrew API; App Store ids live only in the opt-in role; the skills pin is an exact tag |
| `10-bootstrap` | a real bootstrap: mise, packages, casks, pre-existing Homebrew apps left alone |
| `20-runtime-env` | node resolves in interactive, login and empty-environment shells |
| `30-drift` | a deleted dotfile or package is reported and repaired |
| `40-removal` | switching to `work` removes only the allowlisted personal apps |
| `50-ai-tooling` | skills at the pinned release, the settings merge on a real machine, herdr and OpenCode, the agent CLIs (`claude`, `codex`, `omp`) from mise |
| `60-conquer` | the role installs the Tailscale client and daemon; the join is a no-op when connected and prints the OIDC login URL when not |
| `70-identity` | git identity with the configurable email, private GPG files with this OS's pinentry and the public keys imported, the YubiKey-aware signing task, ssh config with the 1Password agent |
| `80-macos-extras` | Finder and keyboard preferences applied and current; with the desktop role the Dock order, the iTerm2 profile, the Alacritty theme, Talat |
| `95-doctor-update` | doctor passes on a converged machine; update --dry-run leaves it converged |
| `90-linux-desktop` | with the desktop role on Linux: 1Password, VS Code and Brave from their vendors' repositories, Alacritty, Ghostty, Docker with the user in its group, Obsidian as a Flatpak, no drift |

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

The two VMPal VMs ("Ubuntu VM 2", "macOS VM 1") both mount the host's
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

## What it does not do yet

Slices 0 to 6 of [the plan](docs/planning/plan.md#5-slices) are built and
run on the two test VMs: the package inventory and the personal/work split,
the runtime contract, the Conquer client, the AI tooling, and identity. Still
to come:

- the Conquer join against the real network: the role installs Tailscale and
  runs the OIDC login, but the Headscale URL is a placeholder until the
  details are settled (ADR 0001 D-23);
- the Dock on `studio` pins Spotify and Brave with the desktop list, but not
  Talat or Slack: mise refuses a Dock whose apps do not exist yet, and both
  arrive after the Dock phase (a task, the App Store role);
- anything needing admin rights or extra permissions on a Mac: the
  automatic software-update check, the terminal's App Management
  permission and the Notification Center banner time (Full Disk Access)
  are not managed;
- on a Linux desktop: Cursor (no supported Linux arm64 channel) and Firefox
  (Ubuntu's own snap) are not declared; 1Password's desktop app exists for
  x86_64 only (arm64 gets the CLI), and its SSH agent is switched on in the
  app's settings by hand;
- the rehearsed migration of the existing Macs, moving an existing
  `~/.ssh/config` into `~/.ssh/config.d/`, and the rename of the public
  skills repo (slice 10).

## Where things live

| Path | What |
|------|------|
| `bootstrap.sh` | the one command; POSIX sh |
| `mise*.toml`, `.miserc.toml` | the declared state, one file per layer |
| `zsh/`, `ghostty/`, `git/`, `gnupg/`, `ssh/`, `bin/`, `tmux/`, `zellij/`, `herdr/`, `alacritty/`, `claude/` | dotfile groups and the Claude settings source |
| `tasks/` | the shell tasks mise runs: `remove-packages`, `merge-claude-settings`, `migrate`, `tailscale-join` |
| `test/` | the bats suite and its fixtures |
| `docs/adr/0001-orchestrator.md` | the orchestrator decision, every finding, every executed result |
| `docs/planning/plan.md` | proposal v4, open decisions, the review ledger, the slices |

## Licence

MIT. See [LICENSE](LICENSE).
