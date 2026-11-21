#!/usr/bin/env bats
# tasks/system-update (ADR 0001 D-40): the whole system's own update, which a first install runs once
# and `update` runs on purpose. apt on Debian-family Linux (and snaps where there are any); Homebrew and
# Apple's softwareupdate on macOS, never restarting the Mac. Non-mutating: uname, apt-get, snap, brew
# and softwareupdate are stubs that log their calls; sudo is the fake.
load helpers

setup() {
  fresh_home
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export CALLS="$BATS_TEST_TMPDIR/calls" FAKE_SUDO=passwordless FAKE_SUDO_STATE="$BATS_TEST_TMPDIR/sudo-unlocked"
  : > "$CALLS"
  stub uname 'echo "${FAKE_OS:-Linux}"'
  stub apt-get 'echo "apt-get[$DEBIAN_FRONTEND] $*" >> "$CALLS"; case " $* " in *" ${FAKE_APT_FAIL:-none} "*) exit 1 ;; esac'
  stub snap 'echo "snap $*" >> "$CALLS"'
  stub brew 'echo "brew $*" >> "$CALLS"'
  stub softwareupdate 'echo "softwareupdate $*" >> "$CALLS"
case "$1" in --list|-l) cat "${FAKE_SWU_LIST:-/dev/null}" ;; esac
case " $* " in *" ${FAKE_SWU_FAIL:-none} "*) exit 1 ;; esac'
  # Only the stubs, the fake sudo and the base system: never a real brew, snap or softwareupdate.
  export PATH="$BIN:$FIXTURES/bin/sudo-fake:/usr/bin:/bin"
}
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
apple_updates() {
  export FAKE_SWU_LIST="$BATS_TEST_TMPDIR/swu-list"
  cat > "$FAKE_SWU_LIST" <<'LIST'
Software Update Tool

Finding available software
Software Update found the following new or updated software:
* Label: Safari27.1-27.1
	Title: Safari, Version: 27.1, Size: 172135KiB, Recommended: YES, 
* Label: macOS 27.2.1-26B131
	Title: macOS 27.2.1, Version: 27.2.1, Size: 6065189KiB, Recommended: YES, Action: restart, 
LIST
}

@test "on Debian-family Linux it refreshes apt, upgrades every package without asking, and refreshes snaps" {
  run "$REPO_ROOT/tasks/system-update"
  [ "$status" -eq 0 ]
  [[ "$(sed -n 1p "$CALLS")" == "apt-get[noninteractive] "*" update" ]] || false
  grep -q -E '^apt-get\[noninteractive\] .*-y .*full-upgrade$|^apt-get\[noninteractive\] -y .*full-upgrade' "$CALLS"
  grep -q -x 'snap refresh' "$CALLS"
  # A freshly booted Ubuntu's unattended-upgrades holds the dpkg lock for minutes: apt waits for it.
  [ "$(grep -c 'DPkg::Lock::Timeout=[0-9][0-9]*' "$CALLS")" -eq 2 ]
  ! grep -q -e '^brew' -e '^softwareupdate' "$CALLS" || false
}

@test "on Linux a failed apt upgrade fails the task, so a first install stops and the next run tries again" {
  FAKE_APT_FAIL=full-upgrade run "$REPO_ROOT/tasks/system-update"
  [ "$status" -eq 1 ]
  [[ "$output" == *"system-update: error"* ]] || false
}

@test "on macOS it updates Homebrew and installs the Apple updates that need no restart" {
  apple_updates
  FAKE_OS=Darwin run "$REPO_ROOT/tasks/system-update"
  [ "$status" -eq 0 ]
  grep -q -x 'brew update' "$CALLS"
  grep -q -x 'brew upgrade' "$CALLS"
  grep -q -x 'softwareupdate --install Safari27.1-27.1' "$CALLS"
  ! grep -q '^apt-get' "$CALLS" || false
}

@test "on macOS an Apple update that needs a restart is downloaded and announced, and the Mac is never restarted" {
  apple_updates
  FAKE_OS=Darwin run "$REPO_ROOT/tasks/system-update"
  [ "$status" -eq 0 ]
  grep -q -x 'softwareupdate --download macOS 27.2.1-26B131' "$CALLS"
  ! grep -q -x 'softwareupdate --install macOS 27.2.1-26B131' "$CALLS" || false
  ! grep -q -e '--restart' -e '--all' "$CALLS" || false
  [[ "$output" == *"macOS 27.2.1"*"restart"* ]] || false
}

@test "on macOS a failing Apple update is a warning, not a failed run, and Homebrew is still updated" {
  apple_updates
  FAKE_OS=Darwin FAKE_SWU_FAIL=--install run "$REPO_ROOT/tasks/system-update"
  [ "$status" -eq 0 ]
  [[ "$output" == *"system-update: warning"* ]] || false
  grep -q -x 'brew upgrade' "$CALLS"
}

@test "--dry-run says what it would do and changes nothing; an unknown flag is refused" {
  apple_updates
  FAKE_OS=Darwin run "$REPO_ROOT/tasks/system-update" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry run"* ]] || false
  ! grep -q -e '^brew upgrade' -e '--install' -e '--download' "$CALLS" || false
  run "$REPO_ROOT/tasks/system-update" --dry-run
  [ "$status" -eq 0 ]
  ! grep -q 'full-upgrade' "$CALLS" || false
  run "$REPO_ROOT/tasks/system-update" --bogus
  [ "$status" -eq 2 ]
}
