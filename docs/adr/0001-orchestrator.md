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
  would also build from source: ask Paul whether they are still wanted;
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

### 2026-10-06 — harness constraints (not mise findings)

- The Claude Code auto-mode classifier refused to write a NOPASSWD sudoers
  entry in either VM and refused to start a local HTTP server to feed the VMs.
  Unattended bootstrap in the VMs therefore needs Paul to grant passwordless
  sudo to the VM user himself, and the VMs fetch the repo from GitHub.

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
