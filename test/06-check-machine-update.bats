#!/usr/bin/env bats
# Slice 9: `check-machine` (the checks mise does not make: selection, drift, login shell, 1Password, Conquer,
# the GPG card, the skills pin) and `update` (upgrade on purpose, with the plan shown first). Safe:
# a private copy of the checkout, a fresh HOME and the fake op and tailscale binaries.
load helpers

setup() {
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  fresh_home
  # Fakes first, always: these tests run anywhere, including a workstation with a real 1Password,
  # YubiKey and Tailscale, and must never touch them.
  export PATH="$FIXTURES/bin/op-locked:$FIXTURES/bin/gpg-nocard:$PATH"
  # `update` also updates the machine's own packages (D-40); only the tests about that step, with
  # the task replaced by a logger, let it run.
  export MACHINE_SETUP_SKIP_SYSTEM_UPDATE=1
}

# check-machine and update need mise for every check after the first; CI installs it in 10-bootstrap.
with_mise() { require_mise; export MISE_BIN; MISE_BIN=$(mise_bin); }

@test "check-machine fails on a checkout with no saved selection and says to run bootstrap" {
  with_mise
  run "$CO/tasks/check-machine"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"*"selection"* ]] || false
  [[ "$output" == *"bootstrap.sh"* ]] || false
}

@test "check-machine fails when mise itself is missing, before anything else" {
  [ ! -x "$HOME/.local/bin/mise" ] || skip "this HOME has mise"
  select_envs "$CO" personal - personal-macbook >/dev/null
  MISE_BIN= PATH="$FIXTURES/bin/op-locked:/usr/bin:/bin" run "$CO/tasks/check-machine"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"FAIL"*"mise"* ]] || false
}

@test "check-machine fails when the installed mise is not the version the repo pins" {
  select_envs "$CO" personal - personal-macbook >/dev/null
  FAKE_MISE_VERSION=0.0.1 MISE_BIN="$FIXTURES/bin/fd-probe/mise" run "$CO/tasks/check-machine"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"*"mise: 0.0.1 installed"*"pins v"* ]] || false
}

@test "check-machine reports a locked 1Password as a warning, never a failure" {
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  run "$CO/tasks/check-machine"
  [[ "$output" == *"WARN"*"1Password"*"not signed in"* ]] || false
  ! grep -q "FAIL.*1Password" <<<"$output" || false
}

@test "check-machine finds the signing key gpg-setup writes to ~/.gitconfig.local, which ~/.gitconfig includes" {
  # Found adopting the Mac Studio: the key was only read from ~/.gitconfig itself, so a signing
  # setup warned "git has no signing key".
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  export PATH="$FIXTURES/bin/gpg-card:$PATH"
  printf '[include]\n\tpath = ~/.gitconfig.local\n' > "$HOME/.gitconfig"
  printf '[user]\n\tsigningkey = 0xTESTKEY\n' > "$HOME/.gitconfig.local"
  run "$CO/tasks/check-machine"
  [[ "$output" == *"OK"*"GPG: a card is present and git signs with 0xTESTKEY"* ]] || false
}

@test "check-machine warns about installed Homebrew packages that are neither declared nor listed as unmanaged" {
  # A package installed by hand is on this machine and on no other: the next machine built from the
  # repo would miss it. Declared packages (jq) and the unmanaged list stay quiet.
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  export PATH="$FIXTURES/bin/brew-inventory:$PATH"
  sed -i.bak 's/^unmanaged_brew = .*/unmanaged_brew = "zzz-unmanaged"/' "$CO/mise.toml"
  # A cask Homebrew renamed keeps its old name as a link to the new one (docker -> docker-desktop):
  # the same app, listed twice, so the old name is not a package of its own.
  export FAKE_CASKROOM="$BATS_TEST_TMPDIR/caskroom"
  mkdir -p "$FAKE_CASKROOM/zzz-new-name" && ln -s zzz-new-name "$FAKE_CASKROOM/zzz-renamed"
  run "$CO/tasks/check-machine"
  local line; line=$(grep 'inventory' <<<"$output")
  [[ "$line" != *"zzz-renamed"* ]] || false
  [[ "$line" == *"WARN"*"zzz-undeclared"* ]] || false
  [[ "$line" == *"zzz-cask"* ]] || false
  [[ "$line" != *"jq"* ]] || false
  [[ "$line" != *"zzz-unmanaged"* ]] || false
}

@test "check-machine reports the inventory as OK when every installed Homebrew package is accounted for" {
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  export PATH="$FIXTURES/bin/brew-inventory:$PATH"
  sed -i.bak -e 's/^unmanaged_brew = .*/unmanaged_brew = "zzz-unmanaged zzz-undeclared"/' -e 's/^unmanaged_cask = .*/unmanaged_cask = "zzz-cask zzz-renamed"/' "$CO/mise.toml"
  run "$CO/tasks/check-machine"
  [[ "$output" == *"OK"*"inventory"* ]] || false
}

@test "check-machine reports the Conquer state from tailscale only when the role is selected" {
  with_mise
  # Without the role first: a re-run without --role keeps the saved roles, so the order matters.
  select_envs "$CO" personal - personal-macbook >/dev/null
  PATH="$FIXTURES/bin/tailscale-connected:$PATH" run "$CO/tasks/check-machine"
  [[ "$output" != *"Tailscale"* ]] || false
  select_envs "$CO" personal conquer personal-macbook >/dev/null
  PATH="$FIXTURES/bin/tailscale-needs-login:$PATH" run "$CO/tasks/check-machine"
  [[ "$output" == *"WARN"*"Tailscale"*"login"* ]] || false
  PATH="$FIXTURES/bin/tailscale-connected:$PATH" run "$CO/tasks/check-machine"
  [[ "$output" == *"OK"*"Tailscale"*"connected"* ]] || false
}

@test "check-machine ends with a summary line and exits 1 while the checkout has never been converged" {
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  run "$CO/tasks/check-machine"
  [ "$status" -eq 1 ]
  [[ "${lines[${#lines[@]}-1]}" == check-machine:*checks*failed* ]] || false   # bash 3.2: no negative index
  [[ "$output" == *"FAIL"*"drift"* ]] || false
}

@test "check-machine gives up on a Tailscale that never answers, and says so, instead of waiting for it (F-62)" {
  # On the macOS VM the app's CLI outlived check-machine's alarm and held its pipe: the suite sat for forty minutes.
  with_mise
  select_envs "$CO" personal conquer personal-macbook >/dev/null
  export PATH="$FIXTURES/bin/tailscale-hangs:$PATH"
  local started=$SECONDS
  run "$CO/tasks/check-machine"
  [ $((SECONDS - started)) -lt 40 ]
  [[ "$output" == *"Tailscale: the daemon did not answer"* ]] || false
}

@test "update --dry-run shows the package and tool upgrade plan and changes nothing; unknown flags are refused" {
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  run "$CO/tasks/update" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"update: packages"* ]] || false
  [[ "$output" == *"update: tools"* ]] || false
  [[ "$output" == *"update: skills pinned to v"* ]] || false
  [[ "$output" == *"dry run"* ]] || false
  run "$CO/tasks/update" --bogus
  [ "$status" -eq 2 ]
}

@test "update raises a low soft open-file limit to 10240 before mise upgrades anything" {
  # The same launchd limit as bootstrap's (ADR 0001 F-55): `mise run update` from a Terminal starts
  # mise upgrade with 256.
  select_envs "$CO" personal - personal-macbook >/dev/null
  export NOFILE_PROBE="$BATS_TEST_TMPDIR/nofile"
  MISE_BIN="$FIXTURES/bin/fd-probe/mise" run sh -c 'ulimit -Sn 256 && exec "$@"' sh "$CO/tasks/update" --dry-run
  [ "$status" -eq 0 ]
  [ "$(cat "$NOFILE_PROBE")" = 10240 ]
}

# The system's own packages are part of an upgrade on purpose (ADR 0001 D-40). The task is a logger here.
with_logged_system_update() {
  select_envs "$CO" personal - personal-macbook >/dev/null
  export SYSTEM_UPDATE_LOG="$BATS_TEST_TMPDIR/system-update-calls"; : > "$SYSTEM_UPDATE_LOG"   # not CALL_LOG: the fake mise writes there
  printf '#!/bin/sh\necho "system-update $*" >> "$SYSTEM_UPDATE_LOG"\nexit "${FAKE_SYSTEM_UPDATE_EXIT:-0}"\n' > "$CO/tasks/system-update"
  chmod +x "$CO/tasks/system-update"
  unset MACHINE_SETUP_SKIP_SYSTEM_UPDATE
}

@test "update --dry-run shows the system update's plan without applying it" {
  with_logged_system_update
  MISE_BIN="$FIXTURES/bin/fd-probe/mise" run "$CO/tasks/update" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"update: system"* ]] || false
  [ "$(cat "$SYSTEM_UPDATE_LOG")" = "system-update --dry-run" ]
}

@test "update --yes updates the system's own packages before the declared ones, and stops when that fails" {
  with_logged_system_update
  MISE_BIN="$FIXTURES/bin/fd-probe/mise" run "$CO/tasks/update" --yes
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$SYSTEM_UPDATE_LOG")" = "system-update " ]
  [[ "$output" == *"updating the system's own packages"*"upgrading packages"* ]] || false
  FAKE_SYSTEM_UPDATE_EXIT=1 MISE_BIN="$FIXTURES/bin/fd-probe/mise" run "$CO/tasks/update" --yes
  [ "$status" -eq 1 ]
  [[ "$output" != *"upgrading packages"* ]] || false
}

@test "update refuses a value other than 0 or 1 for MACHINE_SETUP_SKIP_SYSTEM_UPDATE" {
  with_logged_system_update
  MACHINE_SETUP_SKIP_SYSTEM_UPDATE=yes MISE_BIN="$FIXTURES/bin/fd-probe/mise" run "$CO/tasks/update" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"0 or 1"* ]] || false
  [ ! -s "$SYSTEM_UPDATE_LOG" ]
}

@test "update without --yes and without a terminal applies nothing and says how to" {
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  run "$CO/tasks/update" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]] || false
}

@test "check-machine warns when this session's SHELL is not the login shell, so terminals that read SHELL get the wrong one" {
  # Found on the fresh Ubuntu VM: the install made zsh the login shell, but the desktop session kept
  # SHELL=/bin/bash, so Ghostty and Alacritty opened bash without the aliases or fzf (ADR 0001 F-51).
  with_mise
  local login
  if is_macos; then login=$(dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}'); else login=$(getent passwd "$(id -un)" | cut -d: -f7); fi
  [[ "$login" == */zsh ]] || skip "the login shell here is $login, not zsh"
  select_envs "$CO" personal - personal-macbook >/dev/null
  SHELL=/bin/sh run "$CO/tasks/check-machine"
  [[ "$output" == *"WARN"*"SHELL is /bin/sh"*"log out and back in"* ]] || false
  SHELL="$login" run "$CO/tasks/check-machine"
  [[ "$output" != *"SHELL is"* ]] || false
}

@test "check-machine fails on a cask image an interrupted install left attached, and gives the detach command" {
  # Found on the macOS VM: a converge stopped mid-install left ProtonVPN's image attached, and every
  # later converge failed with a bare "hdiutil … exited with code 1" (ADR 0001 F-54).
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  PATH="$FIXTURES/bin/hdiutil-cask-attached:$PATH" run "$CO/tasks/check-machine"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  cask image: protonvpn-6.5.1-021fecae1a9e-ProtonVPN_mac_v6.5.1.dmg is still attached"* ]] || false
  [[ "$output" == *"hdiutil detach /dev/disk7"* ]] || false
  [[ "$output" == *"FAIL  cask image: shottr-1.9-4c2e-Shottr-1.9.dmg is still attached"*"hdiutil detach /dev/disk9"* ]] || false
  [[ "$output" != *"disk10"* ]] || false   # an APFS image's synthesized container is not the one to detach
  # Only images from mise's cask cache: not the system's, not a Homebrew download.
  [[ "$output" != *"disk5"* && "$output" != *"disk6"* && "$output" != *"disk8"* ]] || false
}

@test "check-machine reports no cask image attached when none from mise's cache is, and skips the check without hdiutil" {
  with_mise
  select_envs "$CO" personal - personal-macbook >/dev/null
  PATH="$FIXTURES/bin/hdiutil-clean:$PATH" run "$CO/tasks/check-machine"
  [[ "$output" == *"OK    cask images: none left attached"* ]] || false
  [[ "$output" != *"FAIL  cask image"* ]] || false
  if ! command -v hdiutil >/dev/null; then
    run "$CO/tasks/check-machine"
    [[ "$output" != *"cask image"* ]] || false
  fi
}
