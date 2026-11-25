# machine-setup

[![ci](https://github.com/citypaul/machine-setup/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/citypaul/machine-setup/actions/workflows/ci.yml)
[![licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

**One command turns a Mac or a Linux machine with nothing on it into a finished
working machine. Run it again and it repairs whatever drifted.**

Packages, apps, dotfiles, language runtimes, git and SSH identity, macOS
preferences and AI coding tools are all declared in this repository. The
declaration is layered, so a personal laptop, a work laptop and a headless
server share one base and differ only where they must.

```sh
machine-setup check               # is this machine what the repo declares?
machine-setup update --dry-run    # what would an upgrade of this computer change?
machine-setup update --yes        # upgrade it
machine-setup self-update         # get the newest machine-setup ...
machine-setup converge            # ... and apply it to this machine
```

This is [Paul Hammond](https://github.com/citypaul)'s own setup, published
whole. Read it for ideas, or fork it and
[make it your own](#make-it-your-own).

## Contents

- [What it manages](#what-it-manages)
- [Why it is built this way](#why-it-is-built-this-way)
- [Set up a machine](#set-up-a-machine)
- [Day to day](#day-to-day)
- [How a machine is described](#how-a-machine-is-described)
- [Make it your own](#make-it-your-own)
- [How it is tested](#how-it-is-tested)
- [Supported platforms and known gaps](#supported-platforms-and-known-gaps)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Licence](#licence)

## What it manages

| What | How | Declared in |
|------|-----|-------------|
| Command-line tools | Homebrew bottles, on macOS and on Linux | `mise.toml` |
| Apps | Homebrew casks and the Mac App Store on macOS; the vendors' apt repositories and Flatpak on Linux | `mise/config.macos.toml`, `mise/config.desktop*.toml`, `mise/config.appstore.toml` |
| Runtimes and developer CLIs | mise tools: Node, Rust, Terraform, and CLIs from npm and GitHub releases | `dotfiles/mise/.config/mise/conf.d/machine-setup.toml` |
| Dotfiles | one folder per group, shaped like your home directory, linked file by file into `$HOME` | `dotfiles/<group>/` |
| Identity | git config rendered per machine, GPG public keys, YubiKey commit signing, SSH config that uses the 1Password agent | `dotfiles/git/`, `dotfiles/gnupg/`, `dotfiles/ssh/`, `tasks/gpg-setup` |
| macOS preferences | Finder, keyboard, the Dock, a LaunchAgent that gives GUI apps the shell's `PATH` | `mise/config.macos.toml`, `mise/config.desktop-macos.toml` |
| AI coding tools | Claude Code, Codex, Gemini CLI and OpenCode; skills at a pinned release; a settings merge that keeps hooks other tools added | `tasks/claude-skills`, `tasks/merge-claude-settings` |
| Software you no longer want | removed by name, from an explicit list | the `remove_*` variables in `mise.toml` and the layer files |

## Why it is built this way

- **One tool, not a stack.** The engine is [mise](https://mise.jdx.dev) and
  its `bootstrap` command, plus small shell tasks for what mise does not do.
  No Ansible, no GNU Stow, no Nix. The choice was tested before it was made:
  [ADR 0001](docs/adr/0001-orchestrator.md) records every finding.
- **It starts from nothing.** The first run needs no git, no Homebrew and no
  Xcode Command Line Tools. It installs its own prerequisites, then a pinned
  version of mise, so every machine runs the same engine.
- **It converges; it never upgrades by surprise.** Running it again installs
  what is missing and repairs what drifted. Nothing is upgraded until you run
  `machine-setup update`, which shows its plan first.
- **Removal is a list, never a prune.** A package is removed only when a layer
  names it. Software you installed by hand is left alone, and
  `machine-setup check` reports any Homebrew package that no layer declares.
- **Secrets stay in 1Password.** No secret is written to the repository, to a
  rendered file, to a dry run or to a log. A task that needs one reads it from
  the 1Password CLI at the moment it runs.
- **It can take over a machine you already use.** Dotfiles that GNU Stow
  manages are migrated in one journaled step that rolls back exactly if any
  part fails. See [Taking over a machine](docs/taking-over-a-machine.md).
- **It is proved on clean machines.** Every pull request runs the whole test
  suite, including a real install, on a clean Ubuntu container and on a macOS
  runner. See [How it is tested](#how-it-is-tested).

## Set up a machine

> [!IMPORTANT]
> Run as it stands, this installs Paul's packages, his dotfiles and his git
> identity. That is what you want in a throwaway VM, to watch it work. For a
> machine you keep, [make it your own](#make-it-your-own) first.

On a machine with nothing installed, not even git:

```bash
u=https://raw.githubusercontent.com/citypaul/machine-setup/main/bootstrap.sh; sh -c "$(curl -fsSL $u 2>/dev/null || wget -qO- $u 2>/dev/null || echo 'echo could not download bootstrap.sh >&2; exit 1')" -- --profile personal --role desktop --machine personal-macbook --yes
```

Three flags describe the machine:

| Flag | Chooses | Values in this repository |
|------|---------|---------------------------|
| `--profile` | personal or work. Personal-only apps never reach a work machine, and switching to `work` removes them. | `personal`, `work` |
| `--role` | optional sets, any number of them. Leave it out for a headless machine. | `desktop` (a machine with a screen), `appstore` (Mac App Store apps), `conquer` (Paul's private network) |
| `--machine` | a name for this machine, so it can carry its own exceptions. | `personal-macbook` (Paul's MacBook Pro), `vm` (a test VM), `ci` (the CI runners) |

In a VM, use `--machine vm`. The run asks for your sudo password once,
installs everything, and ends by asking you to log out and back in. The choices are saved, so later runs need no
flags. `--dry-run` shows what would change and changes nothing.

[The first install and `bootstrap.sh`](docs/bootstrap.md) lists what a run
does in order, every flag and the exit codes. If the machine already has
dotfiles and packages of its own, read
[Taking over a machine](docs/taking-over-a-machine.md) before you run
anything.

## Day to day

The first install puts the `machine-setup` command on your `PATH`. It works
from any directory.

| Command | What it does | Flags |
|---------|--------------|-------|
| `machine-setup update` | Upgrades this computer on purpose: the system's own packages (apt and snaps; Homebrew and Apple's updates, never a restart), then the declared packages and tools. Nothing else ever upgrades. | `--dry-run` shows the plan and changes nothing. `--yes` applies it without asking. With neither, it shows the plan and asks. |
| `machine-setup self-update` | Updates machine-setup itself: fast-forwards its checkout to the newest commit of its branch and lists what arrived. It changes nothing else on the computer. | `--dry-run` lists what would arrive. |
| `machine-setup converge` | Applies the repository to this machine: installs what is declared and missing, repairs what drifted, removes what the removal lists name. Upgrades nothing. | `--dry-run` previews. Other flags are passed to `bootstrap.sh`. |
| `machine-setup check` | Checks this machine against the repository and reports each result as `OK`, `WARN` or `FAIL`. | none |
| `machine-setup help`, `--version` | The commands and exit codes; the commit and the checkout the command runs from. | |

Exit codes: `0` done. `1` the command ran and failed, or `check` found
something to fix. `2` an unknown command or flag.

`machine-setup check` on a converged MacBook (some lines left out):

```text
check-machine: OK    selection: profile=personal roles='desktop' machine=personal-macbook
check-machine: OK    drift: none (mise bootstrap status --missing)
check-machine: OK    login shell: /opt/homebrew/bin/zsh
check-machine: WARN  1Password: CLI present but not signed in; roles that need a secret are skipped until 'op signin'
check-machine: OK    inventory: every installed Homebrew formula and cask is declared or listed as unmanaged
check-machine: 9 checks, 0 failed, 1 warnings
```

Two things to know:

- **`update` and `self-update` are different.** `update` changes the
  computer's packages and leaves the repository alone. `self-update` changes
  the repository checkout and leaves the computer alone; run
  `machine-setup converge` afterwards to apply what arrived.
- **`self-update` only fast-forwards.** If the checkout has commits or edits
  of its own, it stops, changes nothing, and prints the `git status` command
  that shows them.

## How a machine is described

A machine is the sum of its layers. Each layer is one mise config file, and
for the same key the later file wins:

```text
mise.toml                              every machine
└─ mise/config.<os>.toml               macOS or Linux, chosen automatically
   └─ mise/config.<profile>.toml       --profile personal | work
      └─ mise/config.<role>.toml       each --role, with an OS-specific part where needed
         └─ mise/config.machine-<id>.toml   --machine <id>
```

Adding a tool to every machine is one line in `mise.toml`:

```toml
[bootstrap.packages]
"brew:ripgrep" = "latest"
```

An app that only a personal desktop Mac gets is one line in
`mise/config.personal.toml`:

```toml
"brew-cask:discord" = { os = "macos", env = ["desktop"] }
```

Add its name to `remove_cask_profile` in `mise/config.work.toml` as well, so
that switching the machine to the work profile removes it.

Two rules are not obvious:

- **Dotfile-group lists replace, they do not merge.** A role or machine file
  states its complete list of groups.
- **Each layer names its own removals.** A layer adds to a `remove_*` variable,
  and one task joins them into the list of packages to remove.

[How a machine is described](docs/configuration.md) has the full table of
layers, the dotfile groups and where everything lives.

## Make it your own

Fork the repository, then change the parts that are personal to Paul. Each of
them lives in one place:

| Change | Where |
|--------|-------|
| The repository the installer clones | `REPO_URL_DEFAULT` in `bootstrap.sh`, and the URL in the one-line install |
| Your name and email for git | `git_name` and `git_email` under `[vars]` in `mise.toml` |
| Your GPG public keys | `files/gpg-public-keys.asc` |
| Your packages and apps | the `[bootstrap.packages]` tables in `mise.toml` and `mise/config.*.toml` |
| Your dotfiles | the files under `dotfiles/<group>/` |
| Your AI tooling | `tasks/claude-skills` installs Paul's `CLAUDE.md`, skills and agents at the release `claude_skills_version` pins; point it at yours, or take it out of the `bootstrap` task's `depends` list in `mise.toml` |
| A role you do not need | `mise/config.conquer*.toml` joins Paul's private network; delete the files |
| Your machines | add `mise/config.machine-<id>.toml` for any machine that needs its own exceptions |

Then run the tests. The safe ones run on any machine in a fresh `HOME` and
change nothing outside it:

```bash
test/run.sh
```

They check, among other things, that every package you declared exists in the
Homebrew API. Some of them state Paul's own choices, such as which dotfile
groups each machine gets; change those to state yours. Push to your fork and the CI workflow runs a real
install on a clean Ubuntu container and a macOS runner.

## How it is tested

The suite is [bats](https://github.com/bats-core/bats-core) files under
`test/`, in two kinds:

- **Safe tests** run anywhere. They use a fresh `HOME`, a private copy of the
  checkout and stand-ins for `sudo`, `op`, `tailscale` and the package
  managers.
- **Mutating tests** run a real install and then check the machine: packages,
  drift repair, removal on a profile switch, runtimes, identity, macOS
  preferences. They refuse to run unless `MACHINE_SETUP_ALLOW_MUTATION=1` is
  set, and belong on a VM or a CI runner.

GitHub Actions runs both kinds on every push and pull request: in an
`ubuntu:24.04` container, as root, from nothing, and on a `macos-15` runner.

Beyond CI, the one-line install has been run on machines restored to a clean
snapshot. On 2026-11-22 it passed on Ubuntu 26.04 (arm64) and on macOS 27
(arm64), each in one uninterrupted run, with the whole suite passing
afterwards. [ADR 0001](docs/adr/0001-orchestrator.md) records that run as
E-29. Paul's own MacBook Pro has run from `main` since 2026-11-21.

[Tests](docs/testing.md) lists what each test file proves and how to run them.

## Supported platforms and known gaps

| Platform | State |
|----------|-------|
| macOS on Apple Silicon | supported; in daily use |
| Ubuntu, arm64 and x86_64 | supported; tested as described above |
| Other Debian-family distributions | accepted by `bootstrap.sh` but untested; `--os-family debian` forces the choice for a derivative it does not recognise |
| macOS on Intel | untested; the `desktop` role is known to stop at the Dock, which pins an app that ships for Apple Silicon only |
| Other Linux families, Windows | not supported; `bootstrap.sh` exits with code `2` and changes nothing |

The limits that matter most before you rely on it:

- The `desktop` role on Linux covers fewer apps than on macOS, and the
  1Password desktop app exists for x86_64 only.
- macOS settings that need admin rights or extra permissions are not managed.
- When it takes over a machine you already use, the dotfile migration rolls
  back on failure but the install after it does not. Back up first.

[Known gaps](docs/known-gaps.md) is the complete list, with the reason for
each.

## Documentation

| Page | Read it when you want to |
|------|--------------------------|
| [The first install and `bootstrap.sh`](docs/bootstrap.md) | know what a run does in order, look up a flag or an exit code, or do a less common job such as switching profile or adding a role |
| [How a machine is described](docs/configuration.md) | add a package, a dotfile group, a role or a machine; see how secrets are handled; find a file |
| [Taking over a machine](docs/taking-over-a-machine.md) | move a machine that GNU Stow manages onto this setup, or rehearse that on a VM |
| [Tests](docs/testing.md) | run the suite, see what each file proves, or try the setup on a VM |
| [Known gaps](docs/known-gaps.md) | check what it does not do |
| [Antigravity desktop and CLI](docs/antigravity.md) | see how one app that needed special handling is installed |
| [ADR 0001](docs/adr/0001-orchestrator.md) | understand why mise was chosen, and read every finding and decision since |
| [The plan](docs/planning/plan.md) | read the original proposal and the reviews of it |

## Contributing

Issues and pull requests are welcome. This is one person's setup, so a fix to
the mechanism (`bootstrap.sh`, `tasks/`, `test/`) is the kind of change that
fits here; your own choice of packages and dotfiles belongs in your fork.

A change to behaviour comes with a test. Run `test/run.sh` before you open a
pull request; CI runs the rest.

## Licence

MIT. See [LICENSE](LICENSE).
