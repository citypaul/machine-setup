# Proposal v4: one-command machine setup for Mac and Linux

**Status:** D0 decided 2026-10-06 (ADR 0001: option A, mise-native; slice 0 done). Remaining §8 decisions open. Double-checked by Codex `gpt-6-astra` over two rounds (ledger §10); not yet converged — the ten open items are design corrections made in this version plus spike gates that need executed evidence, not prose.
**Author:** Claude (Fable 5.1), 2026-10-06 · supersedes v3/v2/v1

## 1. The experience

One command on a machine with nothing on it. At most three answers (profile, roles, machine id) or flags. Afterwards: **converge** (repair, never upgrade), **update** (upgrade on purpose, with a diff), **status** (drift, non-zero exit), **doctor** (the non-tool checks: 1Password, Tailscale, GPG card, skills version).

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/citypaul/dotfiles/main/bootstrap.sh)"                       # fresh Mac
sh -c "$(wget -qO- https://raw.githubusercontent.com/citypaul/dotfiles/main/bootstrap.sh)" -- --profile work       # fresh Ubuntu
sh -c "$(wget -qO- …/bootstrap.sh)" -- --profile personal --role conquer --machine studio
```

Properties P1–P12 as v3 §1 (zero prerequisites; converge-by-inspection with separate upgrade; declarative inventory; written layering algorithm; no secrets in git/rendered files/previews/logs; clean-machine evidence; public skills path untouched with the installer fixed first; work-Mac friendly; second distro is a small delta; fewer moving parts; one language where possible; staged, reversible migration).

## 2. Today

Two repos: `citypaul/.dotfiles` (public; popular for CLAUDE.md + skills + `install-claude.sh`; personal Stow packages `zsh/ tmux/ gnupg/ alacritty/ zellij/ ghostty/ herdr/`) and `citypaul/mac-dev-machine-setup` (Ansible + Homebrew, macOS only, no CI, ~2,200 lines, rejects Linux at `validation.yaml:7`). Behaviours to keep are inventoried in §4.10.

## 3. The tooling decision (re-scored after review)

### 3.1 Gates

G1 bootstrap with ≤1 prerequisite step (any candidate may be installed by the same bootstrap script; only weight beyond one static binary counts) · G2 OS/profile/role/machine layering · G3 no plaintext secrets · G4 CI-testable · G5 managed-Mac friendly (preference; policy unknown, D8) · G6 public skills path untouched · G7 converge-by-inspection, dry run, drift.

### 3.2 Finalists

| | **A. mise-native** | **B2. Minimal Ansible + mise (runtimes)** | **B. chezmoi + Homebrew + mise** | **C. Nix flakes** |
|---|---|---|---|---|
| What it is | `mise bootstrap` + `[dotfile_groups]` + `[tools]` + `[tasks]` in TOML/Tera | Today's repo rebuilt around native modules: `file`/`template` (dotfiles), `osx_defaults` (check-mode aware), `user.shell`, `homebrew`/`apt`/`git`, inventory `group_vars`/`host_vars` for profile/role/machine; mise for runtimes; Ansible itself from Homebrew or pipx | chezmoi for files + always-run idempotent scripts for everything else | nix-darwin + home-manager + nix-homebrew |
| Bootstrap weight | one static binary | brew/pipx + Python (≈2 min); heavier than A, lighter than today | one binary + Homebrew | installer + daemon + APFS volume |
| Layering | config environments; **group lists replace, not union** (verified) → each machine env must list its full group set | inventory groups/host_vars — the most mature model here | prompted data + templates | modules per host — best in class |
| Converge / drift | native `status --missing`, `plan --detailed-exitcode` | `--check --diff` | must be scripted | `switch`; atomic rollback (unique) |
| Package removal | **no `state = "absent"` for brew/apt/cask; `prune` is broad and can delete undeclared Homebrew-installed formulae** (verified) → explicit removal task needed | `homebrew: state=absent`, `apt: state=absent` — native | script | native |
| JSON merge (settings.json + herdr hooks) | **block edits not for JSON** (verified) → jq task | `json_patch`/`jq` task | `modify_` script | native |
| Secrets | `[bootstrap.secrets]` preflight aborts on a missing referenced secret (no env skipping) → explicit auth preflight in bootstrap | vault + `no_log` | 1Password/age built in | agenix/sops |
| Migration from today | `packages import` seeds Homebrew list; groups map 1:1 to Stow dirs | refactor, not rewrite — lowest migration cost | per-file `chezmoi add` | rewrite |
| Maturity | GA 2026-07-09, daily releases, one primary maintainer | 2012; very mature | 2018; very mature | mature; steep |
| Honest summary | Most consolidated and most modern; five of its declarative claims in v3 turned out to need imperative tasks | Boring, complete, known to Paul; the thing he asked whether to move away from | Great for files; everything else is scripts | Best reproducibility; costliest to own |

Rejected without a finalist slot: pyinfra (Python-first Ansible, same gap), comtrya (0.9.2, 2025-04, no secrets), bespoke shell (re-implements A/B2/B).

### 3.3 Recommendation

Run the **risk-driven spike for A** (slice 0, one day, "inconclusive" allowed). Its gates are precisely the mechanisms the review broke: layered removal on a Mac with mixed Homebrew ownership; group composition across envs; machine-file discovery; a locked 1Password; representative casks; JSON merge; partial-migration rollback; non-interactive runtime env. If A passes, adopt A. If A fails or is inconclusive, adopt **B2** — not B — because it has native answers to every broken mechanism and the lowest migration cost; B stays as the dotfiles-only alternative if Paul does not want YAML back. C only if atomic rollback becomes a requirement.

Why still try A first: it is the only option that satisfies P10/P11 outright, and its gaps are each one small task; the question the spike answers is whether those tasks stay small.

## 4. Target architecture (option A; B2 maps section-by-section onto Ansible modules)

### 4.1 Repos

`.dotfiles` → `agent-skills` **after** `install-claude.sh:285` `own_checkout()` accepts both names, with tests for old remote, new remote, fork, tag and SHA (round-one F4, closed). New public `citypaul/dotfiles`, zero secrets. `mac-dev-machine-setup` archived after cutover. `dotfiles-incubator` TBD (D9).

### 4.2 Layout

```
bootstrap.sh
mise.toml                      # base
mise.macos.toml · mise.linux.toml
mise.personal.toml · mise.work.toml
mise.desktop.toml · mise.conquer.toml · mise.ci.toml
mise.machine-<id>.toml         # per machine; env name and file name are the same string (F11)
mise.local.toml                # untracked: [vars] machine, profile, roles — written by bootstrap.sh (F11: vars do not load from miserc)
zsh/ tmux/ gnupg/ alacritty/ zellij/ ghostty/ herdr/ git/ ssh/ claude/     # Stow-style groups
tasks/   doctor · update · remove-packages · merge-claude-settings · migrate · gpg-setup · ensure-mac-permissions · fix-cask-receipts · talat · tailscale-join · agent-skills · iterm-profile · gh-extensions · playwright
test/    bats + ported Python behaviour tests
.github/workflows/ci.yml · docs/adr/
```

### 4.3 Bootstrap

1. Detect OS/arch. 2. macOS: Xcode CLT wait loop; Debian family: `sudo apt-get install -y git curl ca-certificates`. 3. `curl https://mise.run | MISE_VERSION=<pin> sh`. 4. Prompt/flags → write `miserc.toml` (`env = [os, profile, roles…, machine-<id>]`) and `mise.local.toml` (`[vars]`). 5. **Auth preflight** (F5): `op whoami` → if not signed in, drop secret-bearing envs (`ssh`, `conquer`) from this run's `-E` list and say so. 6. `mise bootstrap --adopt citypaul/dotfiles --dry-run` → show → `--yes`. 7. Print mise's follow-ups plus ours.

### 4.4 Converge / update / drift — as v3 §4.4 (closed F2), plus removal

Removal is an **explicit allowlist task** (`tasks/remove-packages`), per manager (`brew uninstall`, `brew uninstall --cask`, `apt-get remove`), driven by `[vars].remove.{brew,cask,apt}` composed per env — exactly today's `*_to_remove_if_installed` lists. `prune` is never run on a machine with pre-existing Homebrew state (F9). CI test: a container with an undeclared, user-installed formula survives a converge; a declared-removed cask disappears.

### 4.5 Runtimes — the nvm contract (F3)

As v3 §4.5 (idiomatic files on; missing-version install verified in spike; `npm:` backend for `agent-browser`/`gemini-cli` so Homebrew `node` never appears; `PNPM_HOME` honoured; Playwright task), with the environment coverage corrected:

| Launch path | Mechanism | Test |
|---|---|---|
| Interactive terminal | `mise activate zsh` in `.zshrc` | `zsh -ic 'node -v'` |
| Login / `zsh -lc` | `.zprofile` | `zsh -lc 'node -v'` |
| `ssh host cmd`, cron, scripts | shims dir prepended in **`.zshenv`** (read by every zsh) | `env -i HOME=$HOME ssh localhost 'node -v'` |
| macOS GUI apps | LaunchAgent via `[bootstrap.macos.launchd.agents]` running `launchctl setenv PATH …` | `open -a` a test app that echoes `PATH` |
| Linux GUI apps | `~/.config/environment.d/mise.conf` | `systemd-run --user` echo |

### 4.6 Identity and secrets (F5, F6)

Lifecycle states as v3 §4.6, but implemented by the **bootstrap preflight** (§4.3 step 5) and a `doctor` check, not by mise's secret preflight — which aborts on a missing referenced secret rather than skipping. Rule (closed F6): secrets only ever enter a task's environment at execution time; never a rendered persistent file, never a dry run, never a log; CI canary assertion. SSH: 1Password agent on Mac and Linux desktop (native app). Headless (D12): **inbound** access via Tailscale SSH needs no key; **outbound** Git/SSH from a headless box needs a credential on disk — either an age-encrypted deploy key decrypted at use time, or a 1Password service-account token, both documented exceptions to "no key on disk", or no outbound git from headless boxes at all.

### 4.7 AI tooling (F12)

`~/.claude/settings.json` is produced by `tasks/merge-claude-settings`: an atomic `jq` semantic merge of our owned keys into the existing file, preserving unknown keys and existing `hooks` entries (herdr's included), written via temp file + rename; tests cover an existing unrelated hook, herdr's hook, repeated application and malformed input. `herdr integration install claude|codex` runs on fresh machines (closed F10). `install-claude.sh --version <tag>` from `[vars]`.

### 4.8 Testing and evidence (F8)

| Class | Where | Proves |
|---|---|---|
| Clean-machine acceptance | `debian:13` + `ubuntu:24.04` containers; **clean macOS = a Tart VM or an erased Mac with asserted absence of Homebrew and CLT** — a fresh user account is user-configuration testing only | real bootstrap incl. missing-prerequisite branches |
| Runner integration | `macos-15`, `ubuntu-24.04` | converge, drift-repair, both profiles, dry-run safety, no-secrets-in-output, removal allowlist, JSON merge, layering |
| Unit | bats; the cask-receipt Python tests move with their script | logic |

Ported guarantees from `test/setup-dotfiles.py` as v3; smoke tests use `&&`. ARM Linux: VM acceptance + weekly paid `ubuntu-24.04-arm`. Mutation testing N/A (shell + TOML) with this matrix as alternate evidence. TDD per slice.

### 4.9 Layer resolution (F9, F11)

1. Env order `[os, profile, roles…, machine-<id>]`; later wins per key (mise's documented rule).
2. **Groups do not union**: `mise.machine-<id>.toml` (or, absent a machine file, the last role file) states the machine's complete `dotfile_groups` list; a CI test asserts every machine env yields a non-empty list containing `zsh`.
3. Removal lists are `[vars]` arrays composed with explicit `{{ vars.remove_brew | concat(...) }}` in the task, not merged by key.
4. Assertions use `mise bootstrap plan --json` (effective resources), not `mise config` (file listing). Three documented scenarios are asserted in CI, invoked from outside the checkout.

### 4.10 Behaviour inventory — as v3 §4.10 (closed F10)

### 4.11 Migration (F7, F14)

`tasks/migrate`, journaled:

1. **Inventory** Stow links, modified targets, `mise dot conflicts`; write a manifest.
2. **Prerequisites with nothing unlinked**: `mise bootstrap files apply` (vendor apt repos + keyrings, `phase = "pre-packages"`) → `mise bootstrap packages apply --update` (metadata refresh is needed on a desktop with existing indexes) → `tools`, `repos`. `--only packages` is **not** used because it excludes `[bootstrap.files]`.
3. **Swap with a journal**: before writing, copy every target that will change to `~/.local/state/dotfiles-migration/<ts>/` and record each path; `stow -D`; `mise dot apply`. On any failure, the rollback handler (`trap`, not `set -e`) removes **only journaled new targets** and restores the saved originals, links and modes — Stow is not asked to re-adopt files it does not own.
4. **Verify**: `status --missing` exit 0, shell smoke, `doctor`.

CI drill: a container with the old Stow layout, failure injected after three replacement writes **and** again during verification; assert the restored tree equals the pre-migration manifest.

## 5. Slices

| # | Slice | Evidence |
|---|---|---|
| 0 | **Risk-driven spike for A** (one day, may be inconclusive): clean Ubuntu container + runner Mac with mixed Homebrew ownership; gates = layered removal, group composition, machine-file discovery, locked 1Password, representative casks (1Password, Ghostty, VS Code), JSON merge, partial-migration rollback, non-interactive runtime env, drift repair | ADR records pass/fail per gate; fail → B2 design pass (§3.3) before any slice 1 |
|   | **Done 2026-10-06**: all gates pass on Ubuntu VM, clean macOS VM and CI; A adopted (ADR 0001). The spike's code is kept as the walking skeleton. | |
| 1 | Walking skeleton on clean Debian/Ubuntu containers + clean Mac VM | clean-machine + runner + drift |
| 2 | Packages from data + explicit removal allowlist + `work-remove` | removal test |
| 3 | Runtimes meeting §4.5 incl. all five launch paths; nvm retired | bats + CI |
| 4 | Tailscale + `conquer` join | **Ubuntu VM 2 on** |
| 5 | AI tooling: skills, JSON merge, herdr integrations | CI + manual |
| 6 | Identity: git, 1Password agent, GPG, YubiKey task | manual |
| 7 | macOS extras | runner + manual |
| 8 | Linux desktop extras incl. native 1Password | VM |
| 9 | Machine layer, `doctor`, `update` | CI |
| 10 | Journaled migration + cutover + installer fix + rename | staged, rehearsed rollback |

Dependencies: 6-on-Linux needs 8; 4-with-pre-auth needs 6; 5's herdr check needs 3.

## 6. Risks — v3 §6 plus: mise's declarative surface keeps needing tasks (watch the spike: if more than the eight known tasks appear, B2).

## 7. Clean-ups now

Delete `~/personal/.dotfiles/mac-dev-machine-setup/` (copied scratch clone incl. a private key); delete the `.dotfiles-linux-install` worktree; VM's apt Node + npm pnpm are replaced in slice 3.

## 8. Decisions for Paul

| ID | Question | Recommendation |
|---|---|---|
| **D0** | Orchestrator: A (mise-native, spike first) → fallback B2 (minimal Ansible + mise)? Or straight to B2? Or B (chezmoi)? Or C (Nix)? | A spike first; B2 fallback |
| D1 | Rename `.dotfiles` → `agent-skills` + new `dotfiles`? | Yes, last slice, installer fixed first |
| D2 | Machine repo public, zero secrets? | Yes |
| D3 | Dotfiles mode: symlink (live edits like Stow) vs copy/template per file? | symlink-each default; template only where OS/profile logic is needed |
| D4 | Linux CLI tools via Homebrew bottles (A: through mise; B2: `homebrew` module) or apt-only? | Homebrew bottles (44/47 verified on arm64) |
| D5 | Retire nvm for mise `[tools]` under the §4.5 contract? | Yes |
| **D6** | Conquer enrollment: pre-auth key (non-interactive; you must be the Headscale admin or get one issued), web + admin approval, or OIDC? Server URL? Do you administer the server? | Pre-auth key if you are the admin |
| D7 | Ubuntu desktop GUI set? | VS Code, Cursor, Ghostty, Alacritty, Brave/Firefox, native 1Password, Obsidian, Docker engine |
| D8 | Work Mac: MDM? known blocks? separate identity/signing? | needed before slice 6 |
| D9 | `dotfiles-incubator`? | fold or archive |
| D10 | Linux targets: Ubuntu + Debian; headless? | yes; `desktop` off = headless |
| D11 | Secrets provider: `op run`/`op read` or `fnox`? | `op` first |
| **D12** | Headless identity: Tailscale SSH inbound + (age-encrypted deploy key / 1Password service token / no outbound git)? | Tailscale SSH + no outbound git unless needed; else documented exception |

## 9. Evidence log — v3 §9 plus (2026-10-06)

- mise `dotfiles.html`: "A more local config file's list replaces the others"; "strict JSON, XML aren't a fit for blocks" (read)
- mise `bootstrap/packages/`: `state = "absent"` only pacman/scoop/zypper; `prune` for brew "removes linked formulae that are no longer needed, including formulae installed by Homebrew itself" (read)
- Ansible `osx_defaults` (check mode), `file`, `user.shell`, `homebrew`/`apt` `state=absent` — module docs (read; one fetch rate-limited, consistent with the reviewer's citations)
- Zsh startup files (`.zshenv` every invocation; `.zprofile` login only) — Zsh manual (read by reviewer)

## 10. Double-check ledger (Codex `gpt-6-astra`, cross-provider, read-only, 2 rounds)

| ID | Sev | Finding | Round 1 → 2 | v4 action |
|---|---|---|---|---|
| F1 | major | Unequal gates; mise omitted; Ansible misjudged on primitives | re-stated | **Fixed**: B2 re-scored with native modules; A vs B2 decided by spike (§3) |
| F2 | major | `run_onchange_` cannot converge | **closed** | — |
| F3 | major | nvm contract; `.zprofile` ≠ ssh/GUI | maintained | **Fixed**: five launch paths with tests (§4.5) |
| F4 | major | rename breaks `own_checkout()` | **closed** | — |
| F5 | major | secret skipping not provided by mise preflight; headless contradicts no-key rule | re-stated | **Fixed**: auth preflight in bootstrap; headless split inbound/outbound, documented exception (§4.3, §4.6, D12) |
| F6 | major | secrets in rendered scripts/previews | **closed** | — |
| F7 | major | rollback fails after partial replacement | maintained | **Fixed**: journaled swap, trap-based rollback, drill after partial writes (§4.11) |
| F8 | major | fresh Mac account ≠ clean machine | maintained | **Fixed**: Tart VM / erased Mac with asserted absence (§4.8) |
| F9 | minor→major | `state="absent"`/`prune` unsupported or dangerous for brew/apt | re-stated | **Fixed**: explicit removal allowlist task; prune never used (§4.4) |
| F10 | major | unowned behaviours; dependencies | **closed** | — |
| F11 | major | groups replace not union; machine env/file naming; vars in miserc; `mise config` | new | **Fixed** (§4.2, §4.9) |
| F12 | major | block edit unsuitable for JSON | new | **Fixed**: jq merge task (§4.7) |
| F13 | major | spike too weak; B fallback hand-waved | new | **Fixed**: risk-driven gates; B2 with its own design pass (§3.3, slice 0) |
| F14 | major | `--only packages` skips pre-package files; apt metadata not refreshed | new | **Fixed** (§4.11 step 2) |

Scope fidelity (round 2): no unrequested additions; the two "removals" (F9, F11) were defects now fixed; no tests removed or weakened. **Status: not converged after 2 rounds** — the v4 fixes are plan-level and unreviewed; round 3 is scheduled against the spike's executed results rather than another prose pass. VERDICT at round 2: issues-found.
