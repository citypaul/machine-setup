# Tests

[Back to the README](../README.md)

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
one-line install from [Set up a machine](bootstrap.md#the-one-line-install) with `--machine
vm`. Then run the suite from `~/.local/share/machine-setup`, where the
one-liner puts the checkout. Two things about the snapshots: on the macOS one
sudo asks for a password, despite its name, and the full suite needs
passwordless sudo, so add it before running the tests; and the macOS VM may
need a second start after a revert, because the snapshot holds a suspended
session that a newer macOS cannot resume.
