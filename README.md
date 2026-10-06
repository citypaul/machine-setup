# machine-setup

One command sets up a Mac or a Linux machine from nothing: packages, dotfiles,
runtimes, identity and AI tooling. What gets installed is selected by a
profile (`personal` or `work`), additive roles (for example `conquer`,
`desktop`) and an explicit machine id. The OS family is detected
automatically.

**Status:** pre-alpha. Slice 0, the orchestrator proof-of-fit spike, is in
progress. Nothing here is ready to run on a real machine yet.

## Where things are

- [docs/planning/plan.md](docs/planning/plan.md): proposal v4, the open
  decisions and the two-round cross-provider review ledger.
- `docs/adr/`: architecture decision records. ADR 0001 will record the
  orchestrator spike result, gate by gate.

## Try it on a disposable machine

Never run this on a workstation yet: it installs packages, links `~/.zshrc`,
and on macOS puts apps in `/Applications`. On a VM or CI runner with nothing
on it (no git, no Homebrew, no Command Line Tools):

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/citypaul/machine-setup/main/bootstrap.sh)" -- --profile personal --role desktop --machine studio --yes
```

It installs its own prerequisites, puts the checkout in
`~/.local/share/machine-setup`, and saves the selection there. Re-running the
same command with no flags converges with the saved selection; `--profile
work` switches profile and removes the personal apps. To run the test suite
on that machine afterwards:

```bash
cd ~/.local/share/machine-setup && MACHINE_SETUP_ALLOW_MUTATION=1 test/run.sh
```

## Checking a machine by hand

On a machine that has been bootstrapped (the checkout is `~/machine-setup` on
the test VMs, `~/.local/share/machine-setup` after the one-liner):

```bash
cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --yes                       # converge with the saved selection
cd ~/machine-setup && ~/.local/bin/mise bootstrap status --missing             # drift check: exit 0 = as declared
rm ~/.zshrc && cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --yes        # break a dotfile, converge repairs it
cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --profile work --yes         # switch profile: personal apps removed
cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --profile personal --yes     # and back
cd ~/machine-setup && MACHINE_SETUP_ALLOW_MUTATION=1 test/run.sh               # the whole suite
```

## Tests

The suite is [bats](https://github.com/bats-core/bats-core) files under
`test/`, one per gate from the slice 0 spike (plan §5), run in name order:

| Files | What they prove | Mutates the machine? |
|-------|-----------------|----------------------|
| `00-bootstrap-cli` | flag validation, OS detection, the saved selection | no (private copy of the checkout, fresh `HOME`) |
| `01-layering` | group lists across profile, role and machine files; personal apps never reach work | no |
| `02-secrets` | locked 1Password drops the Conquer env; the key is read at run time and never printed or stored | no (fake `op` and `tailscale` under `test/fixtures/bin`) |
| `03-merge-claude-settings` | semantic JSON merge keeps herdr's hooks, is idempotent and atomic | no |
| `04-migrate` | journaled Stow-to-mise swap rolls back exactly after partial failure | no |
| `10-bootstrap` | a real bootstrap: mise, packages, casks, Homebrew-owned apps left alone | **yes** |
| `20-runtime-env` | node resolves in interactive, login, empty-environment and ssh shells | after `10` |
| `30-drift` | deleted dotfile or package is reported and repaired | **yes** |
| `40-removal` | switching to `work` removes only the allowlisted personal apps | **yes** |

```bash
test/run.sh                                   # everything; mutating files skip unless allowed
test/run.sh test/03-merge-claude-settings.bats
MACHINE_SETUP_ALLOW_MUTATION=1 test/run.sh    # on a VM or CI runner only
```

`test/run.sh` uses `bats` from `PATH` or clones bats-core into `.cache/`.
Set `MISE_BIN` to point at a mise binary when running the non-mutating files on
a machine where bootstrap has not installed one. Results of every run on the
spike machines are recorded in [docs/adr/0001-orchestrator.md](docs/adr/0001-orchestrator.md).

## Licence

MIT. See [LICENSE](LICENSE).
