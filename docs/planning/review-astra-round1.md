Cross-provider independent review, round 1. **The proposal is a credible starting point, but it does not yet support the “best available design” or “safe convergence” claims.**

References to “proposal” below mean [machine-setup-redesign.md](/private/tmp/claude-501/-Users-paulhammond-Library-Application-Support-Claude-scratch-workspaces-94974f74-29c9-424a-81ec-f7a2efabef77-e14864ff-9258-438f-acdd-93b7d45b1404-scratch-2026-10-06-0d8983/150e16fc-6928-441d-8662-975643aea14d/scratchpad/machine-setup-redesign.md).

1. **F1 — The orchestrator comparison applies unequal gates and misses a material candidate**  
   **Severity:** major  
   **Evidence:** Proposal:54–63 rejects Ansible for bootstrap dependencies, while proposal:120–121 installs Homebrew and its prerequisites before chezmoi. Homebrew can similarly install Ansible; retaining make, stow and the existing Python setup is not intrinsic to Ansible. The unconfirmed prohibition on a provisioning daemon or `/nix` becomes a hard gate despite D8 leaving work policy unknown. Determinate also documents supported nix-darwin integration. Finally, current mise documentation includes machine bootstrap, packages, dotfiles, services and macOS defaults—directly overlapping the proposed orchestration layer. [Ansible formula](https://formulae.brew.sh/formula/ansible), [Determinate integration](https://github.com/DeterminateSystems/determinate), [mise bootstrap](https://mise.jdx.dev/bootstrap.html).  
   **Evidence tier:** read  
   **Suggested direction:** Compare equally simplified designs, including mise bootstrap, against confirmed requirements and total maintenance obligations. Chezmoi may still win; neither Nix nor mise has been demonstrated superior here.

2. **F2 — Change-triggered scripts cannot provide the promised machine convergence**  
   **Severity:** major  
   **Evidence:** Proposal:29 promises convergence, but proposal:103–108 gates packages, runtimes, skills and defaults on script-content changes. After a successful installation, deleting `rg`, removing a skill or changing a macOS default does not change those scripts. A normal apply therefore skips the repair. A completed Tailscale script similarly says nothing about current login or service state. These are documented chezmoi semantics. [Script execution rules](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/).  
   `chezmoi update` also lacks a defined package-update policy: unchanged scripts skip upgrades, whereas a changed Brewfile may upgrade unrelated packages because Bundle upgrades by default. [Bundle upgrade behaviour](https://docs.brew.sh/Brew-Bundle-and-Brewfile).  
   **Evidence tier:** read  
   **Suggested direction:** Define separate reconciliation and upgrade behaviours. Inspect actual state on reconciliation, and test deliberate drift followed by repair. Specify update cadence and ownership for pinned externals, runtimes and skills.

3. **F3 — The proposed mise replacement does not preserve the existing runtime contract**  
   **Severity:** major  
   **Evidence:** Proposal:71,142,153 treats `mise activate zsh` as replacing `.nvmrc` switching, Node unlinking and PNPM setup. Mise requires explicit opt-in for `.nvmrc`; interactive activation also does not configure arbitrary bootstrap scripts, IDE processes or non-interactive shells. [Node configuration](https://mise.jdx.dev/lang/node.html), [shell and shim guidance](https://mise.jdx.dev/dev-tools/shims.html).  
   Current `.nvm_setup:30–44` installs missing project versions and restores the default outside projects. `.zsh_profile:144–155` preserves custom `PNPM_HOME`. I also checked formula metadata: `agent-browser` and `gemini-cli` still depend on Homebrew Node, so removing the old precedence workaround needs a replacement.  
   **Evidence tier:** read, with executed dependency checks  
   **Suggested direction:** Specify `.nvmrc` enablement, missing-version behaviour, default restoration, non-interactive execution through mise, and migration of global PNPM tools. Test these before retiring nvm and its safeguards.

4. **F4 — Repository redirects do not preserve the installer’s checkout identity logic**  
   **Severity:** major  
   **Evidence:** Proposal:84 says the installer needs no changes. However, [install-claude.sh:285](/Users/paulhammond/personal/.dotfiles/install-claude.sh:285) recognises its own checkout by searching remote URLs for `citypaul/.dotfiles`. A fresh clone using `citypaul/agent-skills`, or an existing clone whose remote is updated, fails that predicate. Without `--version`, lines 338–345 then select the latest release instead of the reviewed checkout’s HEAD. GitHub redirects cannot change that local string comparison.  
   The raw-URL example did return HTTP 200, and GitHub documents git redirects; those findings support transport compatibility, not unchanged installer behaviour. [Rename documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository).  
   **Evidence tier:** read, with executed predicate reproduction  
   **Suggested direction:** Update checkout recognition before renaming. Test old and new remotes, explicit tags/SHAs, default checkout installs and supported fork workflows. Keep the old namespace reserved.

5. **F5 — Unavailable secrets are treated as replacement configuration, and headless identity remains unresolved**  
   **Severity:** major  
   **Evidence:** Proposal:125,173 renders placeholders whenever 1Password is unavailable. That condition can recur after onboarding: expired CLI authentication or a locked/unavailable app is not exclusively a first-install state. As written, applying then risks replacing working configuration with placeholders.  
   Proposal:73,194 also promises headless machines with a 1Password SSH agent. The agent requires the desktop app; CLI sign-in alone does not provide it, and Linux Flatpak/Snap installations cannot supply the supported agent. “Age stays available” does not specify an SSH authentication mechanism. [1Password agent requirements](https://developer.1password.com/docs/ssh/agent/).  
   **Evidence tier:** inferred from the specified lifecycle and documented requirements  
   **Suggested direction:** Distinguish first installation, ready, locked and unavailable states. Preserve working configuration when authentication is unavailable, report incomplete setup explicitly, and define a separate headless identity path—or leave headless support pending D10.

6. **F6 — The proposed secret-template path conflicts with the recommended verbose preview**  
   **Severity:** major  
   **Evidence:** Proposal:73,125 places secret reads, including the Conquer key, in templates; proposal:19,136 recommends `apply --dry-run -v`. If the pre-auth key is interpolated into the Tailscale script, chezmoi’s verbose output prints that rendered script, and execution materialises it in a temporary file. This creates a disclosure route before the key is consumed. [Chezmoi script handling](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/).  
   **Evidence tier:** inferred; no implementation exists to confirm the interpolation choice  
   **Suggested direction:** Explicitly prohibit secret values in rendered scripts and previews. Retrieve enrollment credentials at execution time with controlled output, and test that dry-run, verbose output and failure logs contain no credentials.

7. **F7 — The cutover removes working configuration before proving that replacement can complete**  
   **Severity:** major  
   **Evidence:** Proposal:141 removes Stow links immediately before the first apply. If target rendering, package installation or another prerequisite then fails, the existing shell and application configuration has already been disconnected. A prior dry-run cannot guarantee downloads or privileged operations will succeed. No backup manifest, restoration command or interrupted-migration procedure is specified.  
   The existing [setup-dotfiles.sh:105](/Users/paulhammond/personal/.dotfiles/setup-dotfiles.sh:105) preflights every package before linking anything; its tests explicitly protect against partial installation.  
   **Evidence tier:** inferred from the stated sequence  
   **Suggested direction:** Make migration its own tested operation: identify existing link ownership and custom targets, preserve local changes, stage prerequisites before unlinking, and provide a tested restoration path. Exercise failure after unlinking before migrating either Mac.

8. **F8 — The validation plan neither proves first boot nor preserves existing behavioural coverage**  
   **Severity:** major  
   **Evidence:** Proposal:134 runs only `personal + ci`. Hosted macOS and Ubuntu images already contain Homebrew, Node and other dependencies; macOS also contains CLT. Passing those jobs cannot demonstrate the missing-prerequisite branches. [macOS image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md), [Ubuntu image inventory](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md).  
   The smoke command uses semicolons, so successful `rg --version` can hide preceding failures; an equivalent `zsh -fc 'false; false; true'` returned zero. Existing tests cover conflicts, partial installation, custom XDG paths, permissions, failed completions, optional tools and unchanged source files. Those guarantees have no explicit replacement in the proposed suite. The cask-repair unit tests also have no migration destination.  
   **Evidence tier:** read, with executed shell-exit reproduction  
   **Suggested direction:** Separate runner integration checks from genuine clean-machine acceptance. Cover both profiles, failure/recovery and drift. Port behaviour-level safeguards, adapting implementation-specific assertions. Require TDD per slice; mutation N/A needs this stronger alternate evidence. No tests have actually been deleted yet.

9. **F9 — Layer precedence is named, but its conflict semantics are not defined**  
   **Severity:** minor  
   **Evidence:** Proposal:115 combines ordered precedence, add/remove operations and list union without specifying their interaction. For example: base adds Docker, work removes it, then a selected role adds it again. Does the later addition win, or do removals permanently dominate? Role-to-role ordering and invalid combinations are also unspecified. Chezmoi’s native data merge replaces lists; the promised semantics therefore belong to custom logic. [Data-directory merge rules](https://www.chezmoi.io/reference/special-directories/chezmoidata/).  
   Hostname-only selection additionally changes configuration when a hostname changes and cannot distinguish reused default hostnames reliably.  
   **Evidence tier:** read  
   **Suggested direction:** Define an ordered resolution algorithm and conflict examples before building templates. Persist an explicit machine identifier, with hostname as an optional initial default. Test resolution independently of package installation.

10. **F10 — Several current behaviours have no explicit delivery owner, and slices 4–9 are not independent**  
    **Severity:** major  
    **Evidence:** Proposal:45 promises preservation, but proposal:151–162 leaves material operations unassigned. Examples include Talat’s bespoke download/signature verification, the iTerm dynamic profile, GitHub Stack extension installation and agent-browser’s Chromium installation. Preserving existing herdr hook entries also does not install integrations on a fresh machine; the current [herdr task](https://github.com/citypaul/mac-dev-machine-setup/blob/master/ansible/tasks/herdr.yaml) invokes the integration installer for both Claude and Codex. [Talat task](https://github.com/citypaul/mac-dev-machine-setup/blob/master/ansible/tasks/talat.yaml), [CLI post-install tasks](https://github.com/citypaul/mac-dev-machine-setup/blob/master/ansible/tasks/cli-tools.yaml).  
    Linux desktop identity depends on installing the native 1Password app, and credential-based Conquer enrollment depends on identity setup. Thus the claimed unrestricted reordering is incorrect.  
    **Evidence tier:** read  
    **Suggested direction:** Add a behaviour-to-owner/slice/assertion inventory and real dependencies before cutover. Themes/NvChad can use externals and work-removal lists can fit slice 2, but they still need explicit acceptance checks.

**Claim dispositions**

- **Overall claim — broken (see F1–F10).** The plan does not establish best available choice, convergence, compatibility or safe cutover. **Tier: read/inferred.**
- **1. Orchestrator decision — broken (see F1, F2).** Unequal bootstrap gates and an omitted overlapping candidate undermine the selection rationale. **Tier: read.**
- **2. Public compatibility — broken (see F4).** URL redirects hold; checkout identity and default version selection do not. **Tier: read/executed.**
- **3. Layering model — broken (see F9).** Expressible in principle, but conflict resolution and machine identity remain underspecified. **Tier: read.**
- **4. Bootstrap and secrets — broken (see F5–F8).** Authentication, preview safety and clean-machine evidence are incomplete. **Tier: read/inferred.**
- **5. Homebrew on Linux — could not verify.** Tier 1 ARM64 support and sampled bottles hold; full resolved inventory, footprint, source-build exposure and end-to-end PATH behaviour were not tested. [Homebrew support](https://brew.sh/2025/11/12/homebrew-5.0.0/). **Tier: read/executed.**
- **6. Mise replacing nvm — broken (see F3).** The required compatibility settings and execution environment are missing. **Tier: read/executed.**
- **7. Slices — broken (see F7, F8, F10).** Recovery, preservation gates and actual dependencies need to precede cutover. **Tier: read/inferred.**
- **8. Lost behaviours — broken (see F10).** Several post-install operations lack explicit ownership and acceptance evidence. **Tier: read.**

**Coverage**

Read the complete proposal; the local dotfiles installer, shell/runtime configuration, Claude settings, README installation sections, CI/release workflows and complete dotfiles test file. Retrieved the public provisioning repository’s inventory, Brewfiles, orchestration files and relevant task files, including its cask-repair tests. Consulted primary documentation for chezmoi, mise, Homebrew, GitHub, 1Password, Headscale and Nix-related alternatives.

Executed the raw rename URL check, installer-identity predicate reproduction, shell-exit reproduction, and formula metadata checks for twelve relevant packages.

Explicitly **not checked**:

- Any actual installation, migration, upgrade, rollback or provisioning test.
- A real repository rename, skills.sh listing continuity or fork installation.
- Complete package resolution, disk usage, timing or every ARM64 bottle.
- Live 1Password, YubiKey, Tailscale/Headscale enrollment, DNS or network access.
- Work-Mac policy, the private incubator, or the separate Linux worktree.
- Contents of the excluded local provisioning copy, `.ssh/`, `personal-keys.yaml`, or hook `node_modules`.

The Headscale interpretation is defensible **for joining an existing Conquer network**: the client is Tailscale pointed at Headscale. It does not establish server provisioning. D6 should explicitly settle that boundary and the enrollment method; default web enrollment may require administrator approval unless delegated to OIDC. [Headscale registration methods](https://headscale.net/stable/ref/registration/).

Scope fidelity — unrequested additions: F1  
Scope fidelity — unrequested removals: F3, F4, F7, F10  
Scope fidelity — removed/weakened tests: F8

VERDICT: issues-found