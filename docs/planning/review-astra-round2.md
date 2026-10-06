V3 fixes several earlier omissions, but it is not ready to become the implementation contract. The strongest problem is that its package-removal strategy can remove unrelated software while failing to remove the intended work-profile apps.

Line references below refer to [machine-setup-redesign-v3.md](/private/tmp/claude-501/-Users-paulhammond-Library-Application-Support-Claude-scratch-workspaces-94974f74-29c9-424a-81ec-f7a2efabef77-e14864ff-9258-438f-acdd-93b7d45b1404-scratch-2026-10-06-0d8983/150e16fc-6928-441d-8662-975643aea14d/scratchpad/machine-setup-redesign-v3.md). Closures below are **plan-level closures**, not claims that implementation tests have passed.

**Findings**

1. **F9 — Package removal is unsupported on the target managers; pruning has a different, broader scope**
   - **Severity:** major
   - **Evidence:** Lines 157, 165 and 178 depend on `state = "absent"` or `[vars].prune`. Mise supports declarative absence for pacman, scoop and zypper—not apt, brew or brew-cask. Its prune command does not consume a named removal list: brew pruning can remove undeclared formulae installed by Homebrew itself; cask pruning skips Homebrew-owned casks. Thus an existing work Mac can retain the unwanted casks while losing unrelated manually installed formulae. [Package removal semantics](https://mise.jdx.dev/bootstrap/packages/#remove-a-package-declaratively), [prune command](https://mise.jdx.dev/cli/bootstrap/packages/prune.html).
   - **Evidence tier:** read.
   - **Suggested direction:** Define explicit, manager-specific removals with an ownership boundary. Test an existing Homebrew installation containing both unwanted managed apps and unrelated user-installed tools. Do not substitute general pruning for a removal allowlist.

2. **F7 — Rollback fails after the replacement has partially applied**
   - **Severity:** major
   - **Evidence:** Lines 206–209 restore by re-running Stow, but test failure only immediately after unstowing. If mise first creates a replacement `.zshrc` or symlink and then fails elsewhere, Stow can refuse that conflicting target. Its [implementation explicitly detects non-owned targets](https://github.com/aspiers/stow/blob/master/lib/Stow.pm.in). `set -e` supplies no rollback handler. Furthermore, `mise dot save` saves tracked files; v3 never establishes the required tracking/checkpoint coverage. [History semantics](https://mise.jdx.dev/history.html#saving).
   - **Evidence tier:** inferred from the documented sequence and source.
   - **Suggested direction:** Specify a journaled restoration procedure that removes only migration-created targets and restores prior files, links and permissions. Exercise failure after several replacement writes and during final verification. Prove checkpoint coverage before relying on it.

3. **F11 — Role and machine selection do not implement the specified layer algorithm**
   - **Severity:** major
   - **Evidence:** Line 158 says group selections are unioned. Mise instead replaces earlier `dotfile_groups` lists, so adding Conquer-specific groups can deselect the base shell groups. [Group selection](https://mise.jdx.dev/dotfiles.html#selecting-groups). Lines 90 and 99 also select `machine-studio` while storing `machines/studio.toml`; environment discovery does not automatically map those names. `[vars]` in `miserc.toml` does not enter normal configuration through the [early-settings loader](https://github.com/jdx/mise/blob/main/src/config/miserc.rs). Finally, line 159’s `mise config` lists loaded files rather than asserting resolved resource values. [Environment discovery](https://mise.jdx.dev/configuration/environments.html), [config listing](https://mise.jdx.dev/cli/config/ls.html).
   - **Evidence tier:** read.
   - **Suggested direction:** Write one concrete base/profile/role/machine example using supported filenames and variable locations. Explicitly compose group selections, and assert the effective packages and deployed targets—including invocation outside the checkout.

4. **F12 — The Claude settings strategy uses an operation unsuitable for JSON**
   - **Severity:** major
   - **Evidence:** Line 140 proposes a block edit of `~/.claude/settings.json`. Mise block edits use comment markers; its documentation explicitly excludes strict JSON from this mechanism. This does not establish valid JSON or preserve hook arrays correctly. [Edit-entry limitations](https://mise.jdx.dev/dotfiles.html#edit-entries).
   - **Evidence tier:** read.
   - **Suggested direction:** Use an atomic, semantic JSON merge with explicit ownership of settings and hook entries. Test existing unrelated hooks, herdr hooks, repeated application and malformed input.

5. **F5 — Secret preflight does not provide the promised environment skipping; the headless alternative contradicts the key policy**
   - **Severity:** major
   - **Evidence:** Lines 129–134 attribute safety to resolving every declared secret. Mise resolves only secrets referenced by selected file templates; a missing referenced secret aborts bootstrap rather than skipping its environment. Task-only `op read` inputs receive no such preflight automatically. [Secret-input semantics](https://mise.jdx.dev/bootstrap/secrets.html). Separately, line 227’s `encrypt = true` encrypts saved history, while restored files remain unencrypted—contradicting line 179’s “no key file on disk.” [History encryption](https://mise.jdx.dev/history.html#encrypted-shared-files).
   - **Evidence tier:** read.
   - **Suggested direction:** Explicitly design authentication preflight, task skipping, incomplete-state reporting and retry. For headless identity, distinguish inbound Tailscale access from outbound Git/SSH authentication, and either preserve the no-key-on-disk requirement or document a deliberate exception.

6. **F3 — `.zprofile` does not establish the claimed SSH and GUI runtime environment**
   - **Severity:** major
   - **Evidence:** Line 119 places shims in `.zprofile` and claims this covers GUI applications and `ssh host cmd`. Zsh reads `.zprofile` only for login shells; a remote non-interactive command ordinarily does not read it. GUI applications need their own environment integration. The proposed `zsh -lc` test specifically exercises a login shell and therefore cannot prove the broader claim. [Zsh startup rules](https://zsh.sourceforge.io/Doc/Release/Files.html), [mise shim guidance](https://mise.jdx.dev/dev-tools/shims.html).
   - **Evidence tier:** read.
   - **Suggested direction:** Specify separate terminal, remote-command, scheduler and IDE launch paths. Test with an uninherited environment and the actual launch mechanism. Keep the missing-version-on-directory-entry requirement gated until demonstrated.

7. **F8 — A fresh Mac account is still accepted as clean-machine evidence**
   - **Severity:** major
   - **Evidence:** Lines 148 and 189 permit a fresh user account to prove missing-prerequisite branches. Homebrew and Xcode Command Line Tools are system-wide; creating a user does not remove them. That acceptance path can pass while the first real Mac bootstrap fails.
   - **Evidence tier:** inferred from the shared system installation state.
   - **Suggested direction:** Require a clean macOS VM or erased test installation with asserted prerequisite absence. Keep fresh-account testing, but classify it as user-configuration testing.

8. **F13 — The spike cannot substantiate its advertised gates, and fallback requires another design pass**
   - **Severity:** major
   - **Evidence:** Line 188 claims pass/fail against G1–G7 from three brews, one apt package and basic dotfiles/runtime checks. It does not exercise layered removals, machine discovery, locked secrets, mixed Homebrew ownership, representative casks or partial migration. Several confirmed failures above could coexist with a successful spike. Option B’s paragraphs do not supply replacement semantics for those mechanisms.
   - **Evidence tier:** inferred.
   - **Suggested direction:** Make the spike risk-driven: include the failing boundary cases above and representative packages from Paul’s inventory. A one-day limit is reasonable as a timebox, with “inconclusive” allowed. If A fails, reuse the outcome-oriented slices but require a B-specific design and proof before implementation.

9. **F1 — Ansible is still rejected on a factually incorrect comparison**
   - **Severity:** major
   - **Evidence:** Line 59 claims no native primitives for dotfiles, defaults or login shell, and that everything requires shell modules. Ansible supplies [file/symlink management](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/file_module.html), [macOS defaults with check-mode support](https://docs.ansible.com/projects/ansible/latest/collections/community/general/osx_defaults_module.html), and a [`user.shell` parameter](https://github.com/ansible/ansible/blob/devel/lib/ansible/modules/user.py). The incumbent repository’s implementation choices do not establish a platform limitation.
   - **Evidence tier:** read.
   - **Suggested direction:** Re-score a minimal Ansible design using those primitives and mise for runtimes. Mise may still win, but compare actual custom code, maintenance and migration costs. Adding Nix and mise to the table fixes the omission, not this reasoning error.

10. **F14 — The package-staging sequence omits prerequisites for third-party apt repositories**
    - **Severity:** major
    - **Evidence:** Line 205 selects only packages, tools and repos. Mise explicitly excludes `[bootstrap.files]` from `--only packages`, including files marked `pre-packages`. Additionally, writing a vendor repository definition does not refresh apt metadata automatically; automatic refresh happens only when package lists are absent. A desktop with existing Ubuntu indexes can therefore fail to locate a newly introduced vendor package. [Pre-package files](https://mise.jdx.dev/bootstrap/files.html#files-before-packages), [apt refresh behaviour](https://mise.jdx.dev/bootstrap/packages/apt.html#metadata-refresh).
    - **Evidence tier:** inferred from the proposed sequence and documented behaviour.
    - **Suggested direction:** Include repository keys/definitions and a deliberate metadata refresh in the prerequisite phase. Test with populated Ubuntu indexes and the vendor repository initially absent. Refreshing metadata need not upgrade installed packages.

**Round-one finding dispositions**

| Finding | Disposition and deciding evidence |
|---|---|
| F1 | **re-stated — comparison still misrepresents Ansible.** Mise is now evaluated and managed-Mac policy is qualified, but line 59 contradicts native module documentation. |
| F2 | **accepted — closed.** Lines 101–109 separate convergence, upgrades and drift; native state inspection and `status --missing` support that contract. |
| F3 | **maintained — non-interactive runtime coverage remains incorrect.** Line 119 conflicts with shell startup rules. The remaining runtime contract is substantially clearer. |
| F4 | **accepted — closed.** Line 79 places the checkout-name fix and old/new/fork/tag/SHA tests before rename. Actual rename remains unexecuted. |
| F5 | **re-stated — unavailable-secret handling is not implemented by the cited primitive, and headless key handling contradicts its invariant.** Secrets and history documentation decide this. |
| F6 | **accepted — closed.** Line 134 prohibits persistent secret interpolation and requires execution-time retrieval, output redaction and canary failure tests. Those tests remain to be implemented. |
| F7 | **maintained — rollback does not recover partial replacement.** Lines 206–209 omit cleanup of new targets; Stow conflict handling defeats the claimed restoration. |
| F8 | **maintained — first-boot evidence remains inadequate on the permitted Mac path.** Containers, `&&` and explicit preservation tests address the other original defects. |
| F9 | **re-stated — the specified algorithm conflicts with native semantics.** Package removal/pruning and group/discovery rules produce F9 and F11 above. |
| F10 | **accepted — closed.** Lines 163–182 assign the previously missing behaviours and correct dependencies. Implementation errors within that inventory are separately reported above. |

**Claim dispositions**

- **Overall revised claim — broken (see F1, F9, F11, F13).** Option A is a credible candidate, but its claimed fit is not established. **Tier: read/inferred.**
- **1. Fresh fixes — broken (see F3, F5, F7, F8, F12, F14).** Several new mechanisms contradict documented behaviour. **Tier: read/inferred.**
- **2. Mise behaviour claims — broken (see F5, F9, F11, F12).** Convergence/status, npm tooling and pre-package files exist; the attributed removal, skipping and editing semantics do not hold. **Tier: read.**
- **3. Spike and fallback — broken (see F13).** The spike can pass without testing several claimed gates. **Tier: inferred.**
- **4. Layer resolution — broken (see F9, F11).** Key precedence does not imply supported absence, list union or automatic machine-file discovery. **Tier: read.**
- **5. Migration and rollback — broken (see F7).** The failure drill does not exercise partially applied replacements. **Tier: inferred.**
- **6. Remaining completeness — broken (see F5, F8, F13, F14).** Headless identity, clean-Mac evidence and repository initialization remain unresolved. **Tier: read/inferred.**

**Coverage**

Read v3 and the review brief; checked primary mise documentation and relevant configuration source, Ansible module documentation/source, Zsh startup documentation and Stow conflict handling. Executed read-only public fetches and confirmed that the decisive package, dotfiles, secrets and system-files documentation matched the `v2026.10.3` tag. Compared the revised ledger against the previously established repository evidence.

**Not checked:** no provisioner execution, package installation, clean-machine boot, live VM, SSH/GUI runtime test, authentication, rename, migration or rollback rehearsal. Did not re-audit every existing package/task or perform a new Nix installation comparison. Did not review v1/v2 as alternative proposals. No prohibited paths were opened and no files or application state were changed.

Existing test preservation is now explicitly promised; F8 concerns the validity of new acceptance evidence rather than removal of existing coverage. Interpreting Conquer as a client joining an existing Headscale server is defensible; it does not establish Headscale server provisioning.

Scope fidelity — unrequested additions: none  
Scope fidelity — unrequested removals: F9, F11 — unintended package deletion and weakened profile/role/machine configuration  
Scope fidelity — removed/weakened tests: none

VERDICT: issues-found