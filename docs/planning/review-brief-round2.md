# Round 2 — cross-provider independent review

Thank you for round one. Every finding has a host action in the ledger below. **The artifact under review is now `machine-setup-redesign-v3.md`** in this directory (v1 and v2 remain for reference; do not review them). The task, original scope, constraints and scope-fidelity rules from the round-one brief (`review-brief.md`) still apply unchanged.

## What changed since round one

Between your round one and this round the author independently found that `mise bootstrap` (GA 2026-07-09; `[dotfile_groups]` 2026-10-05) overlaps the whole orchestration layer, which coincides with your F1. v2 re-opened the tooling decision as a three-way comparison (mise-native / chezmoi+Homebrew+mise / Nix) with Ansible, pyinfra and comtrya evaluated explicitly, because the owner asked "should we use Ansible, something more modern, or just shell?". v3 then addressed F2–F10. The recommendation is now **option A, mise-native, behind a one-day proof-of-fit spike with option B as the written fallback**.

## Ledger — please accept, maintain, or re-state each finding on evidence

| ID | Severity | Host action | Where in v3 | Evidence the author relies on |
|---|---|---|---|---|
| F1 | major | Fixed | §3 | mise release notes v2026.6.6 / v2026.7.4 / v2026.10.3 (gh api, executed); Determinate macOS/MDM pages (read); Ansible re-judged on primitives, not bootstrap weight |
| F2 | major | Fixed | §1, §4.4, §3.3 | mise docs: `bootstrap` compares declared vs actual; `"latest"` accepts any installed version; upgrades only via `packages upgrade` (bootstrap/packages/apt.html, bootstrap.html, read). Drift-repair CI test specified |
| F3 | major | Fixed | §4.5 | mise lang/node.html: idiomatic files off by default (read); `agent-browser`/`gemini-cli` depend on Homebrew `node` (formulae API, executed) → moved to `npm:` backend; shims for non-interactive; `PNPM_HOME` preserved; missing-version auto-install flagged "verify exact setting in spike" |
| F4 | major | Fixed | §4.1 | your reproduction of `own_checkout()`; fix + tests precede the rename |
| F5 | major | Fixed | §4.6, D12 | mise bootstrap/secrets.html: all secrets resolved before any write; skipped envs reported; 1Password agent needs native app (read) |
| F6 | major | Fixed | §4.6 | mise redacts secrets from plans/dry runs/status (read); rule: secrets only in execution-time env; CI canary assertion |
| F7 | major | Fixed | §4.11 | four-stage migration; `mise dot conflicts`, `--only packages,tools,repos`, `mise dot save`; old checkout kept for rollback; CI failure drill |
| F8 | major | Fixed | §4.8 | clean-machine containers vs runner integration vs unit; ported guarantees from `test/setup-dotfiles.py`; `&&` |
| F9 | minor | Fixed | §4.3, §4.9 | mise environments.html: later env wins per key (read); removal-as-value; explicit machine id |
| F10 | major | Fixed | §4.10 | behaviour inventory with owner slice + assertion; corrected dependency graph |

## What to scrutinize hardest this round

1. **The fixes are fresh and unreviewed.** Sweep §4.4–§4.11 and §3 as first-class review work, not as a checklist of ledger closures.
2. **Option A's claims against mise's actual documented behaviour**: converge semantics, `status --missing`, `[bootstrap.files]` for third-party apt repos (`phase = "pre-packages"`), `[dotfile_groups]` vs Paul's Stow layout, secrets preflight and redaction, `npm:` backend for CLIs, `mise activate --shims`. Where the docs do not support a claim, say so.
3. **Is the proof-of-fit spike (slice 0) sufficient to de-risk a four-month-old GA feature** with near-daily releases and one primary maintainer, and is "option B with the same slices" a genuine fallback or hand-waving?
4. **Layer resolution (§4.9)**: does "removal as a value + later wins" actually hold under mise's TOML merge, and does `[vars].prune` + `packages prune` do what §4.9 says?
5. **Migration (§4.11)**: can `mise dot apply` coexist with or replace Stow symlinks safely; is the rollback real.
6. **Anything a world-class setup should have that is still missing.**

## How to respond

Same format as round one: findings (title, severity, evidence, tier, direction); then claim dispositions for the overall claim and each of the six areas above; coverage with an explicit not-checked list; the three scope-fidelity lines; and exactly one `VERDICT:` line. For each round-one finding, state `accepted — closed`, `maintained — <strongest surviving form>`, or `re-stated — <new form>`, naming the evidence that decided it. Do not close a finding out of deference.

Read-only, as before: no writes, commits, pushes, messages or state mutation. Do not open anything under `mac-dev-machine-setup/.ssh/`, `personal-keys.yaml`, or `claude/.claude/hooks/node_modules`.
