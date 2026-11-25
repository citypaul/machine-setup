# Known gaps

[Back to the README](../README.md)

What this setup does not do, with the reason for each. Identifiers such as
D-38 or F-68 are entries in [ADR 0001](adr/0001-orchestrator.md), where the
finding or decision is written up.

- the Conquer join against the real network: the role installs Tailscale and
  runs the OIDC login, but the Headscale URL is a placeholder until the
  details are settled (ADR 0001 D-23);
- a Mac that already has Slack from the App Store: the desktop role now
  installs Slack as a Homebrew cask (ADR 0001 D-38), so delete the App Store
  copy before the first converge there;
- the Dock on an Intel Mac: Talat is pinned and ships Apple Silicon builds
  only, so the Dock phase stops there until the list is changed (D-38);
- anything needing admin rights or extra permissions on a Mac: the
  automatic software-update check, the terminal's App Management
  permission and the Notification Center banner time (Full Disk Access)
  are not managed;
- Ghostty needs OpenGL 4.3; a VM whose virtual GPU offers less (the VMPal
  test VMs offer 4.1) closes it at once. The `vm` machine starts it with Mesa's
  software renderer instead (`LIBGL_ALWAYS_SOFTWARE=1`); real hardware keeps
  the GPU;
- on a Linux desktop: 1Password's desktop app exists for x86_64 only (arm64
  gets the CLI), and its SSH agent is switched on in the app's settings by
  hand; Google Chrome is not declared (Google publishes no Linux arm64
  build);
- moving an existing `~/.ssh/config` into `~/.ssh/config.d/` for you, and
  carrying over a machine's own git settings: both are done by hand before a
  takeover (see [Taking over a machine that Stow manages](taking-over-a-machine.md));
- `--skip-system-update` leaves no marker, so the next converge without it
  runs the first-install update (ADR 0001 D-40); write the marker by hand on
  a machine you adopt;
- four apps on Paul's MacBook Pro that a rebuilt machine will not get, named
  in `unmanaged_cask` in `mise.toml`: `font-pt-mono` (its download answers
  401), `battle-net` and `steam` (mise cannot install them), `lazyworktree`
  (mise cannot read its tap) (F-68, D-43);
- `check-machine` cannot see that a cask needs a formula, so such a formula
  must be declared beside the cask, as `ghostscript` is for `mactex` (F-69);
- `mise run update` runs its own `apt-get update` without the retry
  bootstrap has for a lock held just after boot (F-66);
- the remaining Macs, and the rename of the public skills repo (slice 10).
