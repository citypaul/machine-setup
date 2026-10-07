# ADR 0001: Orchestrator for machine-setup

**Status:** accepted 2026-10-06 · **Decides:** plan.md D0 · **Decision:** option A, mise-native

## Context

Plan v4 (`docs/planning/plan.md` §3) left two finalists: **A** mise-native
(`mise bootstrap` + `[dotfile_groups]` + tasks) and **B2** minimal Ansible with
mise for runtimes. The cross-provider review (plan §10) required the choice to
be made by an executed, risk-driven spike rather than prose. Paul confirmed on
2026-10-06: try A first, mise only; B2 is the written fallback.

## Decision

**Option A, mise-native, is adopted.** Every gate and drift repair passed on
the Ubuntu VM (50/50), on the clean macOS VM (50/50) and on GitHub Actions
(both jobs green on pull request #1, merged as 5bf7ba6). The gaps the review
predicted all exist and all stayed small: four shell tasks
(`remove-packages`, `merge-claude-settings`, `migrate`, `tailscale-join`)
and three one-line facts in `bootstrap.sh` (cd into the checkout, export the
mise dir, trust the checkout durably). B2 (minimal Ansible + mise) is not
needed; it stays in plan §3.2 as the recorded fallback.

Consequences carried into the next slices: machine-wide runtimes move to the
global mise config (F-19); the ssh and GUI launch paths still need executed
evidence (slice 3); Linux has no `brew` binary, so formula removal there is
reported, not done, until a decision says otherwise (D-04).

## Gates (plan §5, slice 0)

Each gate is asserted by a bats test under `test/` and run on
`ubuntu:24.04` (container), `macos-15` (runner), the Ubuntu VM and the clean
macOS VM. Verdicts are filled in from executed runs only.

| # | Gate | Test | Linux | macOS | Verdict |
|---|------|------|-------|-------|---------|
| 1 | Layered removal with mixed Homebrew ownership | `test/40-removal.bats` | pass (apt; brew formulae unexercised, no `brew` on Linux) | pass: mise-owned cask on the clean VM, Homebrew-owned cask and undeclared formula on the `macos-15` runner | **pass** |
| 2 | Dotfile-group composition across env files | `test/01-layering.bats` | pass (VM, CI) | pass (VM, CI) | **pass** |
| 3 | Machine-file discovery (env name = file name) | `test/01-layering.bats` | pass (VM, CI) | pass (VM, CI) | **pass** |
| 4 | Locked 1Password handling | `test/02-secrets.bats` | pass (VM, CI; fake op) | pass (VM, CI; fake op) | **pass** |
| 5 | Representative casks (1Password, Ghostty, VS Code) | `test/10-bootstrap.bats` | n/a | pass (clean VM and CI; mise poured all three + `code` binary) | **pass** |
| 6 | JSON merge of `~/.claude/settings.json` preserving herdr hooks | `test/03-merge-claude-settings.bats` | pass (VM, CI) | pass (VM, CI) | **pass** |
| 7 | Partial-migration rollback | `test/04-migrate.bats` | pass (VM, CI) | pass (VM, CI) | **pass** |
| 8 | Non-interactive runtime env | `test/20-runtime-env.bats` | pass: interactive, login, empty-env zsh (VM, CI) | pass (VM, CI, incl. a shadowing node in /usr/local/bin) | **pass** (ssh and GUI paths: slice 3) |
| + | Drift repair | `test/30-drift.bats` | pass (dotfile and apt package; VM, CI) | pass (dotfile and brew formula; VM, CI) | **pass** |

## Findings log

Executed facts, newest last. Each entry says what was run and what it changes
in the design. `mise 2026.10.3 macos-arm64 (2026-10-05)` unless stated.

### 2026-10-06 — documentation reads (mise docs at tag v2026.10.3)

- **F-01 Entry point.** A repo with `mise.toml` + source files is a *bootstrap
  project*: `mise bootstrap --from <url>` (checkout at
  `$MISE_DATA_DIR/bootstrap-repo`, or `--from-dir`). `--adopt` is for a global
  mise config dir or a shared-history setup repo. Plan §4.3 step 6 said
  `--adopt`; corrected. We clone with `git` ourselves and run `mise bootstrap`
  inside the checkout (see F-07 for why).
- **F-02 Plan JSON does not cover dotfiles.** `mise bootstrap plan --json`
  reports accounts, packages, files, services, firewall, compose. Dotfile
  assertions must use `mise dot status --json`; package assertions
  `mise bootstrap packages status --json`. Plan §4.9 point 4 corrected.
- **F-03 No declarative removal for brew/apt/cask.** `state = "absent"` is only
  pacman/scoop/zypper. `mise bootstrap packages` has `apply import prune status
  upgrade use where` and no `remove`. `prune --manager brew` removes *any*
  linked formula outside the declared closure, including Homebrew-installed
  ones; `prune --manager brew-cask` removes only mise-owned casks with intact
  receipts and skips Homebrew-owned ones. Confirms plan §4.4: an explicit
  allowlist task; prune never runs on a machine with pre-existing Homebrew.
- **F-04 Casks are poured by mise itself** (Homebrew API + download + install
  into `/Applications`), not by shelling out to `brew`. A Homebrew-owned cask
  with `.metadata` satisfies a `brew-cask:` entry without ownership transfer.
  mise-poured casks carry `.mise-cask.toml`, not Homebrew `.metadata`, so
  `brew uninstall --cask` may not recognise them (gate 1 must show this).
- **F-05 Secrets.** `[bootstrap.secrets]` maps names to env vars; only inputs
  referenced by *selected templates* are resolved, before any mutation; a
  missing one aborts. `mise bootstrap secrets status --missing` exits 1.
  `--prompt-secrets` exists. Task-time `op read` gets no preflight, so the
  1Password auth check stays in `bootstrap.sh` (plan §4.3 step 5).
- **F-06 `unapply`.** `mise bootstrap unapply <env>` removes files,
  directories, user services and dotfile entries an env contributed; packages,
  repos and compose need separate cleanup. `mise dot unapply --group <g>` and
  `mise dot apply --prune` handle deselected groups (verified executed, below).

### 2026-10-06 — executed probes (scratch project, temp `HOME`)

- **F-07 `.miserc*` in the checkout is ignored under `-C`.** With
  `.miserc.toml` (`auto_env = true`) and `.miserc.local.toml` (`env = ["work"]`)
  in the project: `mise -C <proj> config ls` loaded neither (0 platform files,
  0 env files); `cd <proj> && mise config ls` loaded both; `MISE_AUTO_ENV=1
  mise -C …` loaded the platform file. Early-init settings are read from the
  *real* cwd before `-C` applies. Consequence: `bootstrap.sh` and every
  converge/status wrapper `cd` into the checkout; `-C` is not enough.
  Explicit `-E a,b` *does* work with `-C`.
- **F-08 Settings are not templated.** `[settings] dotfiles.root =
  "{{ config_root }}"` is stored literally. Group `root` values are not
  templated either (`root = "{{ config_root }}/zsh"` resolved to
  `~/.dotfiles/{{ config_root }}/zsh`). A group's relative `root` resolves from
  `dotfiles.root` (default `~/.dotfiles`), never from the config file.
  Consequence: `bootstrap.sh` writes `[settings] dotfiles.root = "<checkout>"`
  into the untracked `mise.local.toml`; `MISE_DOTFILES_ROOT` also works.
- **F-09 `settings.yes` is ignored in non-global config** ("ignored for
  security reasons"). Non-interactive runs pass `--yes` / `MISE_YES=1`.
- **F-10 Machine-file discovery works.** `mise -C <proj> -E
  work,machine-studio config ls` (cwd `/`) listed `mise.toml`,
  `mise.work.toml`, `mise.machine-studio.toml`. Env name = file name (plan
  §4.2 F11) holds.
- **F-11 Layered var composition works with distinct keys.** Base
  `remove_cask_base`, work `remove_cask_profile`, machine
  `remove_cask_machine`, task `run` using `{{ vars.x | default(value="") }}`
  rendered `base-app spotify discord jellyfin` for `-E work,machine-studio`.
  No self-reference needed (plan §4.9 point 3 simplified).
- **F-12 Group lists replace, confirmed; deselection leaves orphans.** With
  base `dotfile_groups = ["zsh"]` and machine `["zsh","ghostty"]`: `-E
  work,machine-studio` applied both; `-E work` reported the ghostty link as
  `orphaned`; `mise dot unapply --group ghostty --yes` removed it. `mise dot
  apply` created `~/.zshrc` and `~/.config/ghostty/config` as symlinks into the
  checkout (symlink-each); `mise bootstrap status --missing` exited 0 after
  apply and 1 after `rm ~/.zshrc`; re-apply restored the link.
- **F-13 `mise dot status --json` shape.** `{files:[{target, source, mode,
  origin:{config, config_root, environment:[…], source}, state, omitted,
  nested}], edits:[], history:{…}}`. A group is one entry (target `~`, mode
  `symlink-each`); per-file checks come from the filesystem.
- **F-14 `packages status --json` shape.** `{"<manager>": {available,
  packages:[{package, requested_version, desired_state, state,
  installed_version, auto_updates?}]}}`. `secrets status --json` is
  `[{name, env, state}]`.
- **F-15 Local mise install.** `curl https://mise.run | MISE_INSTALL_PATH=… sh`
  installs a single binary and only *prints* the shell-activation line; it
  does not edit rc files.

### 2026-10-06 — target machines

- **Ubuntu VM 2** (VMPal): Ubuntu 26.04 arm64, user `paul` (uid 1000), curl,
  wget, git, sudo (password), python3, zsh 5.9 present; no Homebrew, no mise.
  Host reachable from the guest at 192.168.64.1; no shared folder mounts.
- **macOS VM 1** (VMPal): macOS 27.0.1 arm64, user `paul` (uid 501, admin),
  curl and `/usr/bin/git` shim present, **no Command Line Tools, no
  `/opt/homebrew`**: the clean-Mac evidence class plan §4.8 asks for.
- **GitHub runners**: `macos-15` image has Homebrew 6.x and CLT; the
  `ubuntu:24.04` container has neither curl nor git. `ubuntu-24.04` runner has
  Homebrew at `/home/linuxbrew` (not on PATH).

- **Shared folders.** Both VMs mount the host's `~/Downloads` (VMPal
  `sharedFolders`): `/media/VMPal/Downloads` on Ubuntu (virtiofs, automount)
  and `/Volumes/My Shared Files/Downloads` on macOS. A copy of the working
  tree placed there is visible in both guests without any network service.

### 2026-10-06 — design decisions taken while writing slice 0

- **D-01 bootstrap.sh is POSIX sh** because the one-liner runs under
  `sh -c`; tasks under `tasks/` are bash (present on both OSes).
- **D-02 Selection lives in the checkout**, not in `~/.config/mise`:
  `.miserc.local.toml` holds `env = [profile, roles…, machine-<id>]`,
  `mise.local.toml` holds `[vars] profile/roles/machine` and `[settings]
  dotfiles.root = <checkout>` (F-08). A global `miserc.local.toml` would make
  every project on the machine load `mise.work.toml` and friends.
- **D-03 Removal lists use one var per layer** (`remove_<mgr>_base|profile|
  machine`) concatenated in the task definition (F-11); no list union is
  needed from mise.
- **D-04 macOS bootstrap installs Homebrew** (official installer,
  `NONINTERACTIVE=1`). mise pours into the same prefix and does not need
  `brew`, but cask and formula *removal* needs `brew uninstall`, and Paul's
  shell setup expects `brew shellenv`. Linux does not get a `brew` binary in
  slice 0; formula removal there is reported as skipped (gate 1 records it).
- **D-05 Runtime launch paths** (plan §4.5): `zsh/.zshenv` prepends the mise
  shims dir and `~/.local/bin` for every zsh; `zsh/.zshrc` activates mise for
  interactive shells. `[bootstrap.mise_shell_activate]` is not used because
  it edits `~/.zshrc`/`~/.zshenv` in place and both are group symlinks.
- **D-06 The join task passes the key as a process argument** to
  `tailscale up --authkey`; it is never echoed or written. Slice 4 decides
  whether to switch to `--auth-key file:` to keep it out of `ps`.

### 2026-10-06 — executed: non-mutating gates on the macOS host

- **E-01** `test/run.sh test/0*.bats` with mise 2026.10.3: 34 tests, 33 pass,
  1 skipped (Linux-only). Covers gates 2, 3, 4 (with a fake `op`), 6 and 7 on
  a fresh `HOME` against a private copy of the checkout. RED was recorded first
  (every test failed on a missing `bootstrap.sh`).
- **E-02** `mise run <task>` installs missing `[tools]` before running the task
  (node 24 was installed on first `mise run tailscale-join`, ~8 s). Tasks that
  must not pull tools should be plain scripts or declare `tools = false`
  (to check in slice 3).
- **E-03** `mise bootstrap --dry-run` prints hook commands (`mise run
  tailscale-join`) without running them; no secret value appeared in its
  output, as documented (F-05).

### 2026-10-06 — executed: full suite on Ubuntu VM 2 (26.04 arm64, clean)

- **E-04** `MACHINE_SETUP_ALLOW_MUTATION=1 test/run.sh`: 50 tests, 50 pass,
  0 fail, 22 skip (19 non-mutating tests skipped because mise was not yet
  installed when they ran; 2 macOS-only; 1 ssh path with no sshd). Log:
  `.cache/runs/20261006T195736-full.log` in the VM.
- **E-05** A clean-machine bootstrap (`--profile personal --role desktop
  --machine studio --yes`) took 16.5 s on the VM: apt packages, five
  Homebrew bottles poured by mise into `/home/linuxbrew/.linuxbrew`
  (arm64 bottles, no source builds), node 24, both dotfile groups, the
  settings merge and the removal hook. Second run: 0.4 s, no changes.
- **E-06** Gate 1 on Linux: `cmatrix` (personal, declared removed by work)
  was removed by the allowlist task; `sl` (installed by hand, undeclared)
  survived; switching back to personal reinstalled `cmatrix`. Homebrew
  formula removal on Linux is unexercised because no `brew` binary exists
  there (D-04); the task reports it as skipped.
- **E-07** Gate 8 on Linux: node 24 resolved in interactive, login and
  `env -i … zsh -c` shells via `zsh/.zshenv` shims. The ssh path needs an
  sshd on the VM (slice 3 adds one to the VM for the test).
- **E-09** Non-mutating files re-run on the VM once mise existed
  (`20261006T201133-nonmutating.log`): 34 pass, 0 fail, 1 skip (macOS-only).
  The first attempt had three migration-rollback failures caused by GNU
  `stat -f` in the test's tree snapshot (filesystem status, not file mode);
  the rollback itself was correct.
- **E-08** Drift: deleting `~/.zshrc` and removing apt `tree` were both
  reported by `mise bootstrap status --missing` and repaired by re-running
  `bootstrap.sh` with no flags.

### 2026-10-06 — executed: clean macOS VM, first bootstrap attempt

- **F-16 CLT label format changed.** On macOS 27 `softwareupdate -l` (with
  the `installondemand.in-progress` marker) offers `* Label: Command Line
  Tools for Xcode 27.0-27.0` (space, not dash, before the version); the
  older `…for Xcode-15.x` pattern did not match, so bootstrap fell into the
  `xcode-select --install` wait loop and slept for nine minutes waiting for a
  GUI click. Matcher widened to `Command Line Tools for Xcode.*`.
- `/usr/bin/python3` is also a CLT shim on a clean Mac; `/usr/bin/perl` is
  real. Nothing in bootstrap.sh depends on either.

### 2026-10-06 — executed: first GitHub Actions run (commit f391add)

- **E-10** Both jobs hung in `test/01-layering.bats` and were cancelled after
  20 minutes: the commit predates the `mise_bin` fix, so `command -v mise`
  found the helper's own shell function and recursed. No gate evidence from
  CI yet; the fix batch is the next push. Job timeouts (45/60 min) added.

### 2026-10-06 — executed: full suite on the clean macOS VM (27.0.1 arm64)

- **E-11** `20261006T121134-full.log`: 48 pass, 2 fail, 22 skip. The
  clean-machine bootstrap passed in 368 s: headless CLT via `softwareupdate`,
  Homebrew installer, pinned mise, six formulae and four casks (1Password,
  Ghostty, Visual Studio Code, Spotify) poured by mise, node 24, both dotfile
  groups, the settings merge. Second run: 0.6 s, no changes.
- **E-12** Gate 5 pass: all three representative apps in `/Applications` and
  `/opt/homebrew/bin/code` linked, with no Homebrew involvement in the pour.
- **E-13** Gate 8 and drift repair pass on macOS as on Linux (ssh path still
  unexercised: no sshd on the VM).
- **E-14** Failures: test 39 was a test bug (on a clean Mac the arrange step
  skips, and "brew exists" was later true because bootstrap installed it;
  fixed with an explicit marker). Test 49 is real: the post-packages
  `remove-packages` hook errored while switching to the work profile, so the
  mise-poured Spotify was not removed. Diagnosis below.

- **F-17 Mixed ownership, observed.** After mise poured Spotify,
  `brew list --cask` listed it (Homebrew lists Caskroom directories) but
  `brew uninstall --cask spotify` answered "Cask 'spotify' is not installed"
  (no Homebrew `.metadata`). mise's receipt is
  `Caskroom/spotify/1.3.3.264/.mise-cask.toml` with `Spotify.app ->
  /Applications/Spotify.app` beside it. The removal task now decides
  ownership from `Caskroom/<cask>/.metadata` (Homebrew) versus
  `<version>/.mise-cask.toml` (mise) and removes a mise-owned cask by
  deleting the linked bundles and the Caskroom entry. There is no
  `mise bootstrap packages remove`; this is the small task plan §3.3
  budgeted for.

- **E-15** Gate 1 on the clean Mac after the ownership fix: `bootstrap.sh
  --profile work` ran the allowlist hook, which removed the mise-poured
  Spotify (bundle and Caskroom entry) and left 1Password, Ghostty and VS Code
  in place; `--profile personal` re-poured Spotify in 17 s
  (`test/40-removal.bats`: 2/2 on the second run, after the marker fix). The
  Homebrew-owned cask and undeclared-formula cases run on the `macos-15` CI
  runner, which has pre-existing Homebrew state.

- **E-16** Final full suite on the macOS VM, now with Homebrew present
  (`20261006T122831-full.log`): 50 pass, 0 fail, 2 skip (Linux-only; ssh
  path). Every gate has an executed pass on the clean Mac.
- **E-17** PR CI, `ubuntu:24.04` container: 49/50. Only the
  empty-environment shell test failed: the node shim, run from the checkout
  as working directory, reported `mise.machine-studio.toml` "not trusted"
  although bootstrap had run `mise trust`. Diagnosis in F-18.

- **F-18 Trust is skipped under CI=true.** Reproduced locally: with
  `CI=true`, `mise trust` prints "No untrusted config files found" and writes
  no entry under `~/.local/state/mise/trusted-configs`; a later process
  without `CI` refuses the env-specific files ("not trusted"). bootstrap now
  adds the checkout to the global `trusted_config_paths` setting (guarded
  against duplicates: `settings add` appends blindly) and keeps `mise trust`
  for the interactive case.
- **F-19 `[tools]` in the checkout only apply with the checkout as cwd.**
  The runtime tests pass because bats runs from the checkout; from `$HOME`
  the node shim has no version to resolve. Machine-wide runtimes belong in
  the global config (`~/.config/mise/config.toml`, which bootstrap now
  creates for F-18), managed as a dotfile group or written by bootstrap.
  Slice 3 (the §4.5 runtime contract) owns this; gate 8's assertions must
  then run from `$HOME`, not the checkout.

- **E-18** Paul reproduced the hook failure by hand on the Ubuntu VM from a
  desktop terminal: `sh: 1: mise: not found` inside `mise run
  remove-packages`. Ubuntu's `~/.profile` adds `~/.local/bin` to PATH only
  when the directory exists at login, so a terminal opened before the first
  bootstrap never sees mise. Same root cause as the container (fixed in
  bootstrap by exporting `~/.local/bin` before running mise).

- **F-20 path_helper beats `.zshenv` in login shells on macOS.** On the
  `macos-15` runner, `zsh -lc 'node -v'` printed the preinstalled v22: in a
  login shell `/etc/zprofile` runs `path_helper` after `~/.zshenv`, which
  moves `/usr/local/bin` ahead of the shims dir; `.zshrc` (and so `mise
  activate`) is not read by a non-interactive login shell. Interactive and
  empty-environment shells were already correct. The zsh group gains a
  `.zprofile` that re-prepends the shims dir and `~/.local/bin`, which is the
  §4.5 table's login-path mechanism. The Ubuntu container job is green.

- **E-19** F-20 fix verified on the macOS VM before CI: with a fake
  `/usr/local/bin/node` planted (the directory path_helper promotes),
  `zsh -lc`, `zsh -ic` and `env -i … zsh -c` all answered v24.21.0 while a
  plain `sh` saw the fake; `test/20-runtime-env.bats` 3 pass, 1 skip. The
  new `.zprofile` showed up as drift (`status --missing` exit 1) and the
  next converge linked it.

### 2026-10-06 — slice 2: packages from data (decisions while porting the inventory)

- **F-21 Package entries accept an `env` selector.** Probed:
  `"brew:hello" = { env = ["desktop"] }` appears only when `desktop` is a
  selected environment; `env = "desktop"` and a list both work, and `os`
  combines with it. Used sparingly; ownership of a package normally comes
  from the file it is declared in.
- **D-07 Inventory placement.** `Brewfile.cli` → base layer for both OSes
  (Homebrew bottles poured by mise, plan D4); macOS-only formulae
  (`pinentry-mac`, `mas`, `colima`, `mole`) → macOS layer; `Brewfile.gui`,
  the nine fonts and the App Store apps → the `desktop` role; `Brewfile.
  personal` plus Spotify → personal; the legacy "remove if installed" lists
  → base removal vars, `brave-browser`/`protonvpn` → work removal, Karabiner
  → zap list, Yoink → App Store removal. CI and the test VMs do not select
  `desktop`, so they install the representative apps only.
- **D-08 Deferred, not dropped:** `terraform` is a mise tool (the
  `hashicorp/tap` formula would be a source build under mise); `omp`
  (`can1357/tap`) and `quien` (`retlehs/tap`) are obscure taps that mise
  would also build from source: ask Paul whether they are still wanted
  (answered in D-22);
  `agent-browser`, `gemini-cli` and `herdr` pull Homebrew's `node` and move
  to the npm backend in slices 3 and 5; Talat's download task, the gh-stack
  extension, fzf shell integration and the stale-cask-receipt repair are
  slice 7 tasks.
- **F-22 Third-party tap formulae are source builds under mise** when the
  tap publishes no API JSON (brew.md); only `steipete/tap/codexbar` (a cask)
  remains tap-qualified, in the desktop role.

- **E-20** Slice 2 on Ubuntu VM 2 (arm64, already bootstrapped): the full
  personal bootstrap with the 63 base formulae, the 9 desktop font casks
  (mise pours font casks on Linux), apt, dotfiles, node, terraform and the
  settings merge finished with exit 0 in 255 s (`20261006T210547-slice2-
  bootstrap.log`). All 63 formulae came as bottles; llvm 23 was pulled in as
  a dependency. No source builds.

### 2026-10-06 — slice 3 on the Ubuntu VM: four findings

- **F-23 mise runs no post-install steps.** `brew.md` lists fetch, extract,
  relocate, re-sign, receipt, link; nothing else. Homebrew's `ca-certificates`
  and `openssl@3` create and link `cert.pem` in post-install, so on the VM
  `/home/linuxbrew/.linuxbrew/bin/curl https://github.com` returned no
  response (exit 60, "unable to get local issuer certificate") while
  `/usr/bin/curl` worked, and the pinned skills task failed on it.
  `tasks/fix-brew-certs` replicates both post-installs and runs as the first
  `post-packages` hook; a test checks a brewed curl gets HTTP 200.
- **F-24 `environment.d` is read when the user manager starts.**
  `systemctl --user daemon-reload` did not pick the file up; GUI apps see it
  after the next login. `tasks/session-path` also runs `systemctl --user
  set-environment` for the running session (the Linux counterpart of the
  LaunchAgent).
- **F-25 node default packages install only with a fresh node.** On the
  reused VM node 24 pre-dated `~/.default-npm-packages`, so nothing
  installed; the old pnpm globals are now `npm:` tools, which converge.
- **F-26 Login shell.** Over ssh the VM ran bash (Ubuntu's default), so
  `.zshenv`/`.zprofile` never ran and the VM's pre-existing apt node 22
  answered. `[bootstrap.user] login_shell = "zsh"` on Linux; macOS already
  defaults to zsh. The old setup relied on the Oh My Zsh installer's `chsh`.
- Chrome for Testing has no Linux arm64 build (`agent-browser install`
  says so); the Chromium task is advisory and the test skips there.
### 2026-10-06 — slice 3 and slice 5 decisions

- **D-09 Machine-wide runtimes live in a global conf.d fragment** deployed
  by the `mise` dotfile group (`~/.config/mise/conf.d/machine-setup.toml`),
  not in `~/.config/mise/config.toml`, which bootstrap writes to for
  `trusted_config_paths`; a tracked file must never receive machine-local
  writes. The checkout declares no `[tools]` any more (F-19).
- **D-10 Agent CLIs come from the npm backend on both OSes**
  (`@anthropic-ai/claude-code`, `@openai/codex`, `@google/gemini-cli`,
  `agent-browser`); the `claude-code@latest` cask leaves the desktop role.
  The `codex` cask (the desktop app) stays.
- **D-11 The skills installer is pinned.** `tasks/claude-skills` downloads
  `install-claude.sh` from `citypaul/.dotfiles` at `claude_skills_version`
  (an exact tag, enforced) and runs it with `--version <tag> --agent codex
  --with-opencode`, the options the Ansible playbook used; a marker file
  makes converge a no-op until the pin changes. herdr's integrations are
  best effort, as before.
- CI runs on pull requests and on pushes to `main` only; branch pushes no
  longer trigger a second run.

- **F-27 `install-claude.sh` resolves annotated tags to the tag object.**
  On the Ubuntu VM `--version v4.18.0` printed `Version: dc08fe7d…` and
  then 404'd on `raw.githubusercontent.com/…/dc08fe7d…/CLAUDE.md`: the
  script's `git ls-remote --tags --refs` returns the tag object id for an
  annotated tag, which the raw host cannot serve. `tasks/claude-skills` now
  peels the tag (`refs/tags/<tag>^{}`) and passes the commit. The installer
  fix belongs with the other installer work in slice 10.
- **F-28 `[bootstrap.user].login_shell` cannot run unattended on Linux.**
  A bare `zsh` is ignored with a warning (absolute path required), and with
  `/usr/bin/zsh` mise ran plain `chsh -s`, which asked PAM for a password
  ("Authentication failure") and the failure aborted the whole bootstrap
  before tools and tasks. Replaced by `tasks/login-shell`: `sudo -n usermod`
  on Linux, `sudo -n chsh` on macOS, a message when sudo is unavailable, and
  never a failed run.

- **E-21** Slices 3 and 5 on Ubuntu VM 2 after the fixes
  (`20261006T213448-slice35d.log`): bootstrap exit 0 in 30 s; runtime and
  AI-tooling files 18 pass, 1 skip (Chromium, no arm64 build), 1 fail
  (`herdr integration status` exit code, under investigation). Verified on a
  real machine: node 24 from `$HOME` on all three shell paths, `.nvmrc`
  switching with auto-install, nvm gone, npm-backend CLIs, terraform and
  cargo, the old pnpm globals as tools, zsh as login shell, brewed TLS
  clients verifying certificates, ssh to localhost resolving node 24, the
  session PATH for GUI apps, skills at `v4.18.0` with a no-op second run,
  herdr integrations, herdr's hook preserved by the settings merge, OpenCode
  config.

- **E-22** Slices 3 and 5 on Ubuntu VM 2, final (`20261006T214?-slice35e.log`):
  bootstrap exit 0; `20-runtime-env` and `50-ai-tooling` 20 pass, 0 fail,
  1 skip (no Chrome for Testing build on arm64). Adds to E-21: brewed CLI
  tools (rg, gh, herdr) resolve in login, interactive and empty-environment
  zsh with no `brew` binary, through the prefix added by existence in
  `.zshenv`/`.zprofile`; herdr's `integration status` reports claude and
  codex current.

### 2026-10-06 — slice 4 decisions (Conquer, D6 = OIDC)

- **D-12 No bootstrap-time secret for Conquer.** With OIDC the join is
  `tailscale up --login-server <url>`, which prints a login URL for a browser;
  the task prints it and exits 0, converge confirms later. `bootstrap.sh`'s
  1Password preflight stays, driven by a `secret_envs` var that is empty;
  the gate-4 tests declare one in their private copy so the mechanism stays
  proven. The old `op read` join path and its tests are gone.
- **D-13 Client install.** Linux: Tailscale's apt repository as pre-packages
  files (ASCII-armored signing key vendored in `files/tailscale.asc`,
  identical for Ubuntu and Debian; list templated from `/etc/os-release`),
  `apt:tailscale`, `tailscaled` as a system service, and bootstrap now passes
  `--update` so a repository added in the same run has metadata (plan F14).
  pkgs.tailscale.com serves `resolute` (Ubuntu 26.04), `noble`, `trixie`,
  `bookworm`. macOS: the Tailscale app (its own daemon) with
  `~/.local/bin/tailscale` linked to the app's CLI; mise cannot run a root
  LaunchDaemon for the formula's `tailscaled`.
- **F-29 `[bootstrap.files]` has no `os` field and sources must be UTF-8.**
  The first attempt put `os = "linux"` on the files (ignored with "unknown
  field") and vendored the binary `.gpg` keyring ("stream did not contain
  valid UTF-8"). apt accepts an armored key under `/etc/apt/keyrings`.
- **D-14 Role and profile overlays per OS.** Because files and services have
  no OS selector, bootstrap.sh selects `mise.<env>-<os>.toml` right after
  `<env>` when the checkout has it: `conquer` on Linux loads
  `mise.conquer-linux.toml`. A CLI test pins the env list.
- `timeout` cannot run a shell function, and `sudo` drops PATH; the join task
  uses `perl -e 'alarm'` (portable, macOS has no GNU timeout) and
  `sudo -n env PATH=…` so the same binary (or a test fake) is used.

- **F-30 `mas install` blocks on a Mac not signed in to the App Store.** The
  clean macOS VM's desktop bootstrap hung for minutes in `sudo mas install
  --force …` after installing all 42 casks and 9 fonts; mise cannot skip it.
  **D-15:** App Store apps are their own opt-in `appstore` role, selected
  once a Mac is signed in; the desktop role never carries them.

- **F-36 Services need systemd as PID 1.** In the ubuntu:24.04 CI
  container `mise bootstrap` stops at "refusing unsafe change to bootstrap
  service 'tailscaled'" (there is no init to talk to), so the Conquer
  converge failed there while it passed on the VM (E-23). `bootstrap.sh`
  passes `--skip services` when `/run/systemd/system` is absent on Linux
  and says so; the daemon test skips there too, so containers and WSL1
  converge everything else.
- **F-38 The macOS Tailscale app's CLI blocks until the app is set up.** On
  the clean macOS VM `tailscale status --json` through the app bundle hung
  for 17 minutes inside the final hook (the app had never been opened, so
  its VPN configuration was never approved), and a whole converge hung with
  it. Every CLI call in `tasks/tailscale-join` is now bounded by an alarm;
  on macOS a silent daemon gets the instruction to open the app once. A
  fake whose daemon never answers covers it in `60-conquer`. The block covers
  every command, `version` included: the Conquer test sat 50 minutes in
  `tailscale version` on the macOS VM, so the test reads the app bundle's
  version instead and nothing runs the CLI unbounded.
- **D-32 CI runners take the Conquer role, not the desktop role.** With
  `60-conquer` adding `desktop,conquer`, every macOS job would install the
  whole GUI set (fifty casks, MacTeX: about 50 minutes on the macOS VM,
  E-24) and the Linux job the vendors' repositories and a Flatpak runtime,
  for software the VMs already prove. (The stalled stack runs that
  prompted this were the daemon hang, F-41, not slowness.) The test reads `MACHINE_SETUP_TEST_ROLES` (default
  `desktop,conquer`, what the VMs use) and CI sets it to `conquer`; `80`
  and `90` skip on runners.
- **E-23** Slice 4 on Ubuntu VM 2 (`20261006T215713-slice4c.log`):
  `60-conquer` 5 pass (1 macOS-only skip). Adding `--role conquer` selected
  `conquer,conquer-linux`, wrote the keyring and list (codename `resolute`),
  refreshed apt, installed `tailscale` and left `tailscaled` active; the join
  task reported "already connected" against the connected fake and printed
  the login URL against the needs-login fake.
- **E-24** Slice 2 desktop role on the clean macOS VM
  (`20261006T130647-slice2-bootstrap.log`): the 63 formulae, all 42 casks of
  the desktop role, the 9 fonts and Spotify installed in about 50 minutes,
  MacTeX's 5.7 GB download included; mise asked for sudo only for pkg
  installers. The run then hung in `mas install` (F-30) until stopped; with
  App Store apps moved to the `appstore` role the remaining phases run on
  the next converge (E-25 to follow).

### 2026-10-06 — slice 6 decisions (identity)

- **D-16 Git identity is a rendered template** (`git/gitconfig.tera`, mode
  `template`): name in the base vars, email per profile (`personal` sets it,
  `work` is a placeholder until D8 is answered; superseded by D-20), aliases and settings ported
  from git-setup.yaml, and `[include] path = ~/.gitconfig.local` for
  machine-local state. `tasks/gpg-setup` writes the signing key there only
  when a YubiKey is inserted, so the tracked template never carries a key id.
- **D-17 GPG files are private copies, not links** (`mode = "copy"`,
  `0600`, `~/.gnupg` `0700`), with the pinentry chosen per OS in a template;
  the three public keys from the old repo are vendored (public material) and
  imported by the task; the YubiKey-aware `gpg-auto-sign` wrapper ships in a
  `bin` group.
- **D-18 ssh config is a template that only `Include`s `~/.ssh/config.d/*`**
  and sets the 1Password agent (macOS always; Linux when the socket exists;
  superseded by D-21: every machine).
  Personal host entries stay untracked, because this repo is public. The
  migration of an existing `~/.ssh/config` into `config.d/` is a slice 10
  item.
- **F-31 Templates and the migration journal.** Group files ending in
  `.tera` are not linked by the swap (mise renders them); the migration now
  journals everything mise creates during apply (mtime after a marker) so a
  rollback still restores the tree exactly.

### 2026-10-06 — executed: the full suite on the macOS VM with slices 2-5 (desktop role present)

- **E-25** `20261006T135931-full-s4.log` on macOS VM 1: converge exit 0,
  73 pass, 6 fail. New passes on the Mac: the LaunchAgent PATH for GUI apps
  (`launchctl getenv PATH` lists the shims), agent-browser's browser, drift
  repair of a brewed formula, skills at the pin, herdr, OpenCode. The six
  failures and their causes: `login-shell` undefined on macOS (it lived in
  the Linux layer; moved to the base); brewed `wget` links `openssl@4`,
  whose `OPENSSLDIR` had no `cert.pem` (F-33); work-profile drift from
  `brave-browser` and `tailscale-app` being declared and removed at once
  (moved to personal-only and Conquer-only); the Tailscale CLI symlink
  crash (F-32); the bash 3.2 empty-array error in the join task (D-19).
- **F-32 The Tailscale app's CLI aborts when launched through a symlink**
  ("The current bundleIdentifier is unknown to the registry");
  `~/.local/bin/tailscale` is a wrapper script that execs the binary at
  its real path inside the app bundle.
- **F-33 More than one brewed OpenSSL.** Homebrew ships `openssl@4` next to
  `openssl@3`; each keg has its own `OPENSSLDIR` under `etc/`, and a client
  linked against @4 ignored the @3 bundle. `fix-brew-certs` links
  `cert.pem` under every `etc/openssl@*` whose keg exists.
- **D-19 Tasks run under macOS's `/bin/bash` 3.2.** An empty array under
  `set -u` is a fatal "unbound variable" there, so tasks expand arrays as
  `${arr[@]+"${arr[@]}"}`; `tasks/tailscale-join` and `tasks/migrate` do.

- **F-35 `mise run` auto-installs every declared tool first** (`task.run_auto_install`,
  default true). Once the `mise` dotfile group deploys the tools file, a hook
  such as `post-dotfiles = "mise run login-shell"` installs node, rust,
  terraform, omp and the six npm agents before the phase order reaches
  `tools`; in `04-migrate` that was 6 GB and ten minutes per test home, and
  on a real machine it means a migration or the packages phase installs
  toolchains as a side effect. `[settings] task.run_auto_install = false`
  in `mise.toml` scopes the fix to this checkout; a test now asserts that a
  migration leaves no tool installs behind. Phase order per
  `mise bootstrap --help`: accounts and plugins; pre-packages files and
  hook, packages; privileged files, services, firewall, compose; repos and
  dotfiles (with their hooks); activation, macOS defaults, LaunchAgents,
  user units, user settings; tools (with hooks); plugin packages, the
  post-packages hook, tool-dependent services; the `bootstrap` task and the
  final hook. So only the post-dotfiles hook runs before tools.

### 2026-10-06 — answers from Paul (identity, omp, Conquer)

- **D-20 One git email, overridable per machine.** The address is
  `paul.hammond@gmail.com` for both profiles (base var `git_email`);
  `bootstrap.sh --git-email <addr>` saves an override in `mise.local.toml`,
  later runs keep it, and `--git-email ''` drops it. The profile files no
  longer set the var, because a config environment's file outranks
  `mise.local.toml` (verified with a `{{ vars.a }}` task: base < local <
  env), so an override there could never win. Supersedes the email part of
  D-16 and the pending work identity in D8.
- **D-21 The 1Password SSH agent on every machine.** The rendered
  `~/.ssh/config` always names the agent socket for its OS; the Linux
  socket-exists condition is gone. **F-34** ssh falls back silently when
  the `IdentityAgent` socket does not exist (verified: `ssh -o
  IdentityAgent=/nonexistent/agent.sock -T git@github.com` authenticated
  with the key files), so a headless machine without 1Password loses
  nothing.
- **D-22 omp stays, quien goes.** `omp` is Oh My Pi, a coding agent shipped
  as one binary per OS and arch on GitHub releases (`can1357/oh-my-pi`); it
  is a mise tool through the `github:` backend (verified: `omp` 18.6.1
  installs on macOS arm64 with no build), next to the other agent CLIs.
  `quien` no longer exists in `retlehs/tap` (only `ansimotd` is left) and
  Paul does not remember it, so it is dropped. Closes the question in D-08.
- **D-23 Conquer details deferred.** Paul will settle the Headscale URL and
  enrollment later; the role stays opt-in with the placeholder
  `headscale_url`, and nothing else in the stack waits on it.

### 2026-10-06 — slice 7 decisions (macOS extras and the remaining groups)

- **D-24 macOS preferences are declared, not scripted.** `osx.yaml` maps onto
  mise's friendly `[bootstrap.macos.finder|keyboard]` sections plus raw
  `[bootstrap.macos.defaults]`; a `post-defaults` hook unhides `~/Library`
  and restarts Finder. Defaults are not templated (bootstrap.md), so new
  Finder windows open at "home" (`PfHm`) rather than a `file://$HOME` path:
  the same behaviour, machine-independent. `LSQuarantine = false` is carried
  over as it was. The automatic software-update check is a system-domain
  default that needs admin rights, so it is flagged (D8), not declared.
- **F-37 Hooks merge per key across config files.** The Linux layer's
  `post-dotfiles` replaced the base one while the base `post-packages` still
  ran (CI log), so a later file replaces a hook key wholesale and leaves the
  others. `post-defaults` therefore lives in the macOS layer alone, and a
  second `final` hook would silently replace Conquer's.
- **D-25 The Dock is one declared list, owned by the desktop role on macOS**
  (`mise.desktop-macos.toml`). mise adds, removes and reorders the pinned
  apps and refuses a layout whose apps do not exist, and the Dock phase runs
  before tasks. So Slack (App Store role), Spotify and Brave (personal
  profile), and Talat (a task) are not pinned yet: group-style lists replace,
  and the test machines still use the `studio` machine id without the
  desktop role, so a studio Dock list would fail CI. Slice 9 gives machines
  their own ids and Dock lists. Spacers have no equivalent and are dropped.
- **D-26 Talat is a task** (`tasks/talat`): macOS on Apple Silicon with the
  desktop role; reads the release feed with `plutil` (no jq needed), checks
  Gatekeeper and the developer team id before moving the app into place,
  warns on network failure and fails on a verification failure.
- **D-27 gh extensions are advisory**: `gh extension install` needs a
  signed-in gh, so the task installs `github/gh-stack` when it can and
  otherwise prints the two commands to run.
- **D-28 fzf and autosuggestions without installers.** `.zshrc` sources
  `~/.fzf.zsh` if the old installer wrote it, else `fzf --zsh`;
  `zsh-autosuggestions` is a Homebrew formula the existing `.zshrc` already
  sources from the Homebrew prefix.
- **D-29 Checkouts as `[bootstrap.repos]`**: Oh My Zsh, NvChad on its `v2.0`
  branch (what Paul's config runs; upstream froze it, so an upgrade to 2.5
  is a separate decision for Paul), and `alacritty-theme` (the collection
  `~/.alacritty.toml` imports) with the desktop role. URLs match the
  checkouts already on Paul's Macs so slice 10 adopts them without a
  re-clone. Retired with evidence: the Catppuccin and Dracula clones (no
  config imports them), `zsh-you-should-use` (vendored under a name whose
  plugin file never matched the loader, so it never loaded), the two cask
  receipt scripts (mise owns casks and repairs drift itself, E-13/E-25);
  `ensure-mac-permissions` moves to slice 9's `doctor`.
- **F-39 Pin `[bootstrap.repos]` to a commit.** NvChad has a tag and a branch
  called `v2.0`, so `ref = "v2.0"` resolved to the tag and read `differs`
  after every converge on the Ubuntu VM. `refs/heads/v2.0` read as current
  there only because that old checkout had a local branch: a fresh clone of
  it (CI) is a detached HEAD, which mise compares by local branch name, so it
  read `differs` forever and failed every later drift check
  (`ref_is_current` in `src/system/repos.rs`). A full commit SHA compares by
  SHA and is current everywhere; NvChad is pinned to
  `3091ea58359bb85f087499bd73fbc0a57a935c34`, the v2.0 commit on Paul's Mac.
- **F-40 A sandboxed app's preferences need Full Disk Access.** Writing
  `com.apple.notificationcenterui` (the banner time from `osx.yaml`) failed
  with "failed to synchronize macOS preference domain … may require Full
  Disk Access for your terminal" and stopped the whole converge on the
  macOS VM (every later test failed with it). The banner time is not
  declared; it joins the by-hand list with the software-update check.
- The `tmux`, `zellij` and `herdr` groups join the base list, `alacritty`
  the desktop list; `neovim` joins the base formulae.

### 2026-10-06 — slice 8 decisions (the Linux desktop set, plan D7)

- **D-30 The Linux GUI set and where each piece comes from.** 1Password, VS
  Code (`code`), Brave and Docker Engine from the vendors' apt repositories,
  added as pre-packages files the same way as Tailscale (D-13): the keys are
  vendored under `files/` as ASCII-armored public keys (F-29) and compared
  with the fingerprints the vendors publish: 1Password
  `3FEF 9748 469A DBE1 5DA7 CA80 AC2D 6274 2012 EA22`, Microsoft
  `BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF`, Docker
  `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`; Brave ships its
  keyring as a binary file, re-armored here, fingerprint
  `DBF1 A116 C220 B8C7 164F 9823 0686 B784 2003 8257` (its current key).
  1Password's arm64 repository publishes `1password-cli` only (the first
  Ubuntu VM converge failed with "Unable to locate package 1password"),
  so the desktop app is declared for `linux/x64` and the CLI everywhere.
  Alacritty is Ubuntu's own package. Obsidian is a per-user Flatpak from
  Flathub (aarch64 and x86_64): mise installs neither flatpak nor the
  remote, so a `pre-packages` hook does. Docker's daemon is a declared
  service and a task puts the user in the `docker` group. Not declared:
  Cursor (no supported Linux arm64 channel: Flathub has nothing, the vendor
  publishes an AppImage without a stable URL) and Firefox (Ubuntu ships it
  as a snap already). Mozilla's apt repository has no arm64 packages
  (checked: 404), so Brave is the declared browser. Repositories were
  checked for Ubuntu 26.04 (`resolute`) on arm64 before being declared.
- **F-42 A system Flatpak needs polkit; an unattended run has none.** The
  first desktop converge on the Ubuntu VM failed at "Flatpak system
  operation GetRevokefsFd not allowed for user": `flatpak install --system`
  asks polkit, and a run from a script or ssh has no session to answer.
  Obsidian is a `flatpak-user:` entry and the Flathub remote is added in
  user scope, which need no privilege.
- **D-31 Ghostty on Ubuntu is a task, not a package entry.** There is no
  repository; Ghostty's docs point at the `ghostty-ubuntu` builds (one
  `.deb` per release and architecture). `tasks/ghostty-linux` resolves the
  latest tag from GitHub's redirect (no API call, so no rate limit in CI)
  and installs the file for this release once. The trust decision: a
  community build over TLS from GitHub, the same standing as a Homebrew
  cask; a signed repository would replace it.

### 2026-10-06 — slice 9 decisions (machine layer, doctor, update)

- **D-33 Machine ids.** `studio` is Paul's Mac Studio (personal, desktop):
  the full group list and its own Dock, the desktop list plus Spotify and
  Brave, which the personal profile guarantees. Talat and Slack stay
  unpinned there: mise refuses a Dock layout whose apps do not exist and
  both arrive after the Dock phase (a task; the opt-in App Store role). The
  two test VMs are `vm` (full desktop list) and the runners `ci` (base
  list); the mutating tests read `MACHINE_SETUP_TEST_MACHINE` (default
  `vm`) and CI sets `ci`, next to the roles variable from D-32. Real
  machines beyond studio get their files at cutover (slice 10).
- **D-34 `doctor` makes the checks mise does not**: mise and its pin, the
  saved selection, drift (`status --missing`), the login shell, 1Password
  sign-in, the Conquer state when the role is selected, the GPG card and
  signing key, the skills pin, and whether services can be managed. One
  line per check; `FAIL` means run something first and sets exit 1, `WARN`
  means it works but something is left to do by hand. The two gates that
  stop everything else (no mise, no selection) end the report early.
- **D-35 `update` upgrades on purpose.** Converge never upgrades; `update`
  shows mise's package and tool upgrade plan, applies it only with `--yes`
  (or a yes at a terminal), and reports drift afterwards. mise's own pin
  and the skills pin change through the repo, never here.

### 2026-10-06 — test-harness lessons (not mise findings)

- On a Mac without the Command Line Tools, `/usr/bin/git` is a shim that
  prints "requesting install", pops the CLT dialog and exits 1. The harness
  must not call `git` before bootstrap has run: bats is fetched as a tarball
  with `curl`, and the checkout copy only uses `git ls-files` when
  `xcode-select -p` succeeds.
- `command -v mise` returns the test helper's own `mise` shell function, so
  "is mise installed" must use `type -P`. The first Linux VM run recursed for
  100 s per test instead of skipping.
- `pgrep -f pattern` run from `sh -c "... pattern ..."` matches its own shell;
  use a `[p]attern` so the pattern never matches the command that carries it.
- The macOS guest saw a stale copy of a changed file on the virtiofs share
  for roughly a minute after the host wrote it; re-check the share before
  relaunching.
- A background job started from a VMPal exec call dies with the call unless
  it leaves the call's process group: `setsid nohup …` on Linux, and on macOS
  (no `setsid` binary) `python3 -c 'import os,sys; os.setsid();
  os.execvp(...)'`. Long runs are launched that way and read back from
  `.cache/runs/<timestamp>.log`.

- **The CI container's `$HOME` is not the passwd home.** GitHub sets
  `HOME=/github/home` for container jobs while root's passwd entry says
  `/root`; ssh (and gpg) resolve `~` through passwd, so `ssh -G` ignored the
  deployed `~/.ssh/config` there. Tests name the file with `-F`.

### 2026-10-06 — harness constraints (not mise findings)

- The Claude Code auto-mode classifier refused to write a NOPASSWD sudoers
  entry in either VM and refused to start a local HTTP server to feed the VMs.
  Unattended bootstrap in the VMs therefore needs Paul to grant passwordless
  sudo to the VM user himself, and the VMs fetch the repo from GitHub.

### 2026-10-07 — Ghostty on the Ubuntu test VM

- **F-50 Ghostty needs OpenGL 4.3; the VMPal VM's virtual GPU offers 4.1.**
  On the reinstalled Ubuntu VM Ghostty opened and closed at once: it logged
  "loaded OpenGL 4.1" and "Ghostty requires OpenGL 4.3", and the surface
  failed. With Mesa's software renderer (`LIBGL_ALWAYS_SOFTWARE=1`) it gets
  OpenGL 4.5 and stays up. `mise.machine-vm-linux.toml`, which bootstrap
  selects next to `machine-vm` on Linux only, installs a user launcher entry
  with that override; real hardware keeps the system entry and the GPU.

### 2026-10-07 — the macOS rehearsal on a fresh VM

- **F-48 GNU Stow folds directories, and the migration took their files for
  real ones.** Where a directory did not exist when a package was stowed,
  Stow links the whole directory (`~/.config/ghostty -> ../.dotfiles/
  ghostty/.config/ghostty`). The rehearsal's dry run refused five such
  targets as "real files"; on Paul's Mac three are folded (both Ghostty
  config folders and `~/.config/zellij`; his `~/.gnupg` and
  `~/.config/herdr` are real directories). `tasks/migrate` now detects a
  link into the Stow dir among a target's parents, does not count files
  under it as conflicts, and before the swap unfolds it the way Stow does:
  a real directory with the folded one's permissions and one journaled link
  per entry. Managed files are then replaced as usual; anything else stays
  linked into the old Stow dir and is listed at the end; a rollback
  restores the folded link exactly. The rehearsal's "ROLLBACK EXACT" before
  this fix was vacuous: the injected failure never ran, the conflict check
  stopped first.
- **F-49 bats does not enforce a failing `[[ ]]` mid-test under bash 3.2,
  nor `! cmd` under any bash.** A test for the fold rollback passed with
  status 3 and no "rolled back" in its output. bats documents both: append
  `|| false`. The two new tests do; the rest of the suite is swept
  separately.

### 2026-10-07 — fresh VMs: the one-line install on a vanilla Ubuntu desktop

- **F-45 A fresh Ubuntu desktop has no curl, and `sh -c "$(curl …)"` then
  exits 0.** On the reinstalled Ubuntu 26.04.1 VM (wget and perl present; no
  git, no curl) the README's one-liner printed `curl: not found` and ran an
  empty script, which succeeds, so nothing happened and nothing said so.
  The one-liner now downloads with curl or wget and, when neither works,
  runs `echo could not download bootstrap.sh >&2; exit 1` instead of
  nothing; checked on both paths and with an unreachable URL (exit 1).
  `bootstrap.sh` installs curl itself once it runs.

### 2026-10-07 — slice 10: the first migration rehearsal (macOS VM)

- **F-44 A checkout under the home directory broke the migration plan.**
  Paul's first rehearsal stopped at "0 targets from 11 groups" and then
  "targets[@]: unbound variable": with the checkout at `~/machine-setup`,
  `mise dot status --json` reports the group sources as `~/machine-setup/zsh`,
  and `find` was handed the literal `~`. The tests never saw it because
  their checkout sits beside the test HOME, not inside it. `tasks/migrate`
  expands the `~`, stops with a clear message when a plan lists no files, and
  guards its array expansions for bash 3.2 (D-19); `04-migrate` now also
  migrates a checkout inside HOME. Nothing was written: the dry run stopped
  first.
- **The rehearsal's "before" state must match Paul's Mac, not
  `./install.sh`.** On the Mac only eight Stow packages are live (`zsh`,
  `tmux`, `gnupg`, `alacritty`, `zellij`, `.oh-my-zsh`, `ghostty`, `herdr`);
  `claude` and `opencode` are not stowed (`~/.claude` is a real directory
  the skills installer writes, its linked skills point into
  `~/.agents/skills`), and `~/.oh-my-zsh` is a real Oh My Zsh checkout with
  one custom plugin linked in. On a fresh VM, `install.sh` stows all ten and
  GNU Stow folds `~/.claude` and `~/.oh-my-zsh` into whole-directory links to
  the repo, a layout the Mac never had (and one where the skills installer
  and the `~/.oh-my-zsh` repo declaration would write into, or refuse, the
  dotfiles clone). The README's rehearsal steps install Oh My Zsh first and
  stow only the eight live packages.
- A dry run against a copy of the real `~/.dotfiles` in a throwaway home
  plans 20 targets from 11 groups with no conflicts; the Stow links outside
  machine-setup's groups (the `.oh-my-zsh` plugin, retired in D-29) are left
  pointing into `~/.dotfiles`, which the cutover removes with the old repo.

### 2026-10-07 — executed: slices 2 to 9 on main

- **E-26** With PR #13 merged, CI on `main` runs the whole suite on both
  runners (the ubuntu:24.04 container in about four minutes, the macos-15
  runner in about eleven) and exits on its own. On the test VMs, with the
  same code: macOS VM 1 passed 116 of 116 (9 Linux-only skips), including
  the macOS extras, the Dock and Talat; Ubuntu VM 2 passed 114 of 116 with
  the two hard-coded machine ids PR #13 fixed, then the affected files 33
  of 33, including the whole Linux desktop set. Logs:
  `~/Downloads/machine-setup-runs/` on the host.

### 2026-10-07 — main's first CI run with every slice

- **F-43 A declared service never converges without systemd.** In the CI
  container the Conquer role's `tailscaled` reads `unavailable … unknown`,
  so `status --missing` could never pass there once the role was added.
  A first attempt taught `doctor` to parse mise's status table and ignore
  service rows; it assumed the table lists only unconverged rows (it lists
  all of them) and was fragile even then, so it was removed. Instead the
  container never takes the role (`60-conquer` skips where systemd is not
  PID 1; the Ubuntu VM covers it) and `doctor` uses mise's own exit code.
  The bootstrap test also checked a desktop-only group (Ghostty) and two
  tests a hard-coded machine id; they now follow `MACHINE_SETUP_TEST_MACHINE`.

### 2026-10-07 — CI: the macOS job hung after its last test

- **F-41 A daemon started during a run holds the test runner's pipe.**
  On the macOS runner every test passed within three minutes, then the job
  waited until the 60-minute timeout; GitHub's cleanup reported an orphaned
  `op`. The `1password-cli` cask generates its shell completions by running
  `op completion`, which starts `op daemon`, and the daemon keeps every
  descriptor it inherited, including bats' fd 3, so bats never saw EOF. It
  only shows on a machine where the cask is installed for the first time
  (CI); the VMs had it already. `bootstrap.sh` runs `mise bootstrap` and
  `op whoami` with stdio only (`stdio_only`), and two tests in
  `00-bootstrap-cli` prove neither inherits a descriptor beyond stdio.
  The same hang returned on PR #13's macOS job (116 of 116 passed in ten
  minutes, then nothing). Reproduced on the macOS VM with its daemons
  stopped and inspected as root: the process holding the write end of the
  pipe bats was reading was `op daemon`, on **fd 12**, not 3. bats runs each
  test inside a redirected group, and macOS's bash 3.2 saves the original
  descriptors above 9 without marking them close-on-exec, so every command
  a test starts inherits a copy of bats' output pipe there; Linux's bash 5
  marks them, which is why only macOS hung. (An `scdaemon` holding a pipe on
  fd 3 was a false lead: its fds 3 and 4 are its own internal pipe.) The
  fix closes every descriptor above 2, not 3 to 9: `stdio_only` is a Perl
  exec wrapper (dash cannot name descriptors above 9; Perl ships with macOS
  and is essential on Debian) in `bootstrap.sh`, `doctor`, `update` and the
  test helpers, and the bootstrap tests hold fd 13 open to prove it.
  `test/run.sh` also guards the run: once every planned test has reported,
  bats gets 60 seconds to exit, then the runner names every process
  holding the pipe bats is waiting on (lsof on macOS, /proc on Linux) and
  fails; a synthetic leak fails in nine seconds and names the holder.
