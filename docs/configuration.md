# How a machine is described

[Back to the README](../README.md)

Everything is a mise config file: `mise.toml` in the repo root and one file per
layer in `mise/`. Files load in this order,
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
| `bin` | always | commands linked into `~/.local/bin`: `machine-setup` (see [Day to day](../README.md#day-to-day)) and `gpg-auto-sign`, the YubiKey-aware signing wrapper |
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

## Secrets and 1Password

No secret is ever written to this repo, to a rendered file, to a dry run or to
a log. Tasks that need one (`tailscale-join`) read it from the 1Password CLI at
the moment they run and pass it straight to the process that needs it. When
`op whoami` fails, `bootstrap.sh` drops the roles that would need a secret
from the current run and tells you; run `op signin` and re-run to add them.

## Where things live

| Path | What |
|------|------|
| `bootstrap.sh` | the first install and every converge; POSIX sh |
| `mise.toml`, `mise/config.*.toml`, `.miserc.toml` | the declared state, one file per layer |
| `dotfiles/<group>/` (`zsh`, `rex`, `ghostty`, `git`, `gnupg`, `ssh`, `bin`, `tmux`, `zellij`, `herdr`, `alacritty`, `mise`, `claude`) | dotfile groups and the Claude settings source |
| `dotfiles/bin/.local/bin/machine-setup` | the `machine-setup` command, linked into `~/.local/bin` on every machine |
| `tasks/` | the shell tasks mise runs, among them `remove-packages`, `merge-claude-settings`, `migrate`, `check-machine` and `update` |
| `test/` | the bats suite and its fixtures |
| `docs/adr/0001-orchestrator.md` | the orchestrator decision, every finding, every executed result |
| `docs/planning/plan.md` | proposal v4, open decisions, the review ledger, the slices |
