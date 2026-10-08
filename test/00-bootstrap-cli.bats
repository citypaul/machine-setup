#!/usr/bin/env bats
# bootstrap.sh command-line contract: detection, validation, and the saved per-machine selection.
# Non-mutating: everything runs with --select-only against a private copy of the checkout.
load helpers

# The desktop role has an overlay per OS (mise.desktop-macos.toml: Dock, iTerm2 profile; mise.desktop-linux.toml: the GUI set).
desktop_envs() { if is_macos; then echo "desktop,desktop-macos"; else echo "desktop,desktop-linux"; fi; }

setup() {
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  export PATH="$FIXTURES/bin/op-unlocked:$PATH"
}

@test "an unsupported --os-family is rejected with exit 2 before anything is written" {
  skip_unless_linux
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --os-family rhel --profile work --machine studio --select-only --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"unsupported"* ]] || false
  [ ! -e "$CO/.miserc.local.toml" ]
  [ ! -e "$CO/mise.local.toml" ]
}

@test "--os-family is rejected on macOS, where there is no distro family" {
  skip_unless_macos
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --os-family debian --profile work --machine studio --select-only --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"--os-family"* ]] || false
}

@test "an unknown profile is rejected with exit 2" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile gaming --machine studio --select-only --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"profile"* ]] || false
  [ ! -e "$CO/.miserc.local.toml" ]
}

@test "a non-interactive run with no saved selection and no --profile fails with exit 2 and names the flag" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --machine studio --select-only --yes </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--profile"* ]] || false
}

@test "a non-interactive run with no --machine fails with exit 2 and names the flag" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --select-only --yes </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--machine"* ]] || false
}

@test "--select-only records profile, roles, machine, dotfiles.root and the env list without running mise" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop --role conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  local os; if is_macos; then os=macos; else os=linux; fi
  [[ "$output" == *"envs=personal,$(desktop_envs),conquer,conquer-$os,machine-studio"* ]] || false
  [ "$(env_list_of "$CO")" = "personal,$(desktop_envs),conquer,conquer-$os,machine-studio" ]
  grep -q '^profile = "personal"$' "$CO/mise.local.toml"
  grep -q '^roles = "desktop conquer"$' "$CO/mise.local.toml"
  grep -q '^machine = "studio"$' "$CO/mise.local.toml"
  grep -q "^dotfiles.root = \"$CO\"$" "$CO/mise.local.toml"
}

@test "roles may also be given as one comma-separated list" {
  local os; if is_macos; then os=macos; else os=linux; fi
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop,conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [ "$(env_list_of "$CO")" = "personal,$(desktop_envs),conquer,conquer-$os,machine-studio" ]
}

@test "the detected OS, family and architecture are printed" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile work --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  if is_macos; then
    [[ "$output" == *"os=macos"* ]] || false
  else
    [[ "$output" == *"os=linux"*"family=debian"* ]] || false
  fi
  [[ "$output" == *"arch="* ]] || false
}

@test "re-running without flags reuses the saved selection" {
  "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop --machine studio --select-only --yes >/dev/null
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --select-only --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"envs=personal,$(desktop_envs),machine-studio"* ]] || false
}

@test "changing only --profile keeps the saved roles and machine" {
  "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role desktop --machine studio --select-only --yes >/dev/null
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile work --select-only --yes
  [ "$status" -eq 0 ]
  [ "$(env_list_of "$CO")" = "work,$(desktop_envs),machine-studio" ]
}

# A daemon started during a run (the 1Password CLI starts one when its cask generates completions)
# inherits every descriptor the run had. bats keeps its output pipe on fd 3 and on copies above 9,
# and waits for EOF on it, so a held descriptor hung the macOS CI job after its last test until the
# timeout (ADR 0001 F-41). mise and op must get stdio only; the tests hold fd 13 open to prove it.
prerequisites_present() {
  if is_macos; then xcode-select -p >/dev/null 2>&1 && [ -x /opt/homebrew/bin/brew ]
  else command -v git >/dev/null && command -v curl >/dev/null && [ -e /etc/ssl/certs/ca-certificates.crt ]; fi
}

@test "mise bootstrap runs with stdio only, so a daemon an installer starts cannot hold the caller's pipe open" {
  prerequisites_present || skip "prerequisites missing here; this test must not install them"
  { true >&3; } 2>/dev/null || skip "no descriptor 3 to leak in this harness"
  mkdir -p "$HOME/.local/bin"
  cp "$FIXTURES/bin/fd-probe/mise" "$HOME/.local/bin/mise"
  export FAKE_MISE_VERSION; FAKE_MISE_VERSION=$(sed -n 's/^MISE_PIN="\${MISE_VERSION:-v\([^}]*\)}"$/\1/p' "$REPO_ROOT/bootstrap.sh")
  export FD_PROBE="$BATS_TEST_TMPDIR/fd-probe"
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --machine studio --yes 13>"$BATS_TEST_TMPDIR/held"
  [ "$status" -eq 0 ]
  [ "$(cat "$FD_PROBE")" = "open: none" ]
}

# launchd starts macOS processes, Terminal's shells among them, with a soft limit of 256 open files,
# and mise's npm installs failed with "Too many open files" under it on the macOS VM (ADR 0001 F-55).
# with_fake_mise; then `limits <ulimit commands>` runs bootstrap under them and prints the soft limit
# mise bootstrap started with.
with_fake_mise() {
  prerequisites_present || skip "prerequisites missing here; this test must not install them"
  mkdir -p "$HOME/.local/bin"
  cp "$FIXTURES/bin/fd-probe/mise" "$HOME/.local/bin/mise"
  export FAKE_MISE_VERSION; FAKE_MISE_VERSION=$(sed -n 's/^MISE_PIN="\${MISE_VERSION:-v\([^}]*\)}"$/\1/p' "$REPO_ROOT/bootstrap.sh")
  export NOFILE_PROBE="$BATS_TEST_TMPDIR/nofile"
}
limits() {
  rm -f "$NOFILE_PROBE"
  sh -c "$1"' && exec "$@"' sh "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --machine studio --yes >/dev/null 2>&1 || return 1
  cat "$NOFILE_PROBE"
}

@test "bootstrap raises a low soft open-file limit to 10240 for mise, and never lowers a higher one" {
  with_fake_mise
  [ "$(limits 'ulimit -Sn 256')" = 10240 ]
  [ "$(limits 'ulimit -Sn 20000')" = 20000 ]
}

@test "bootstrap raises the soft open-file limit only as far as a hard limit below 10240" {
  with_fake_mise
  [ "$(limits 'ulimit -Sn 256 && ulimit -Hn 4096')" = 4096 ]
}

@test "the 1Password sign-in check runs op with stdio only" {
  { true >&3; } 2>/dev/null || skip "no descriptor 3 to leak in this harness"
  sed -i.bak 's/^secret_envs = ".*"$/secret_envs = "conquer"/' "$CO/mise.toml"
  export PATH="$FIXTURES/bin/fd-probe:$PATH" FD_PROBE="$BATS_TEST_TMPDIR/fd-probe"
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes 13>"$BATS_TEST_TMPDIR/held"
  [ "$status" -eq 0 ]
  [ "$(cat "$FD_PROBE")" = "open: none" ]
}

@test "a role's per-OS overlay file is selected right after the role when the checkout has one" {
  local os; if is_macos; then os=macos; else os=linux; fi
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [ "$(env_list_of "$CO")" = "personal,conquer,conquer-$os,machine-studio" ]
}

@test "--git-email is saved with the selection, kept by later runs, and dropped by an empty value" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile work --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  ! grep -q '^git_email' "$CO/mise.local.toml" || false   # no override: the base default applies
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --git-email paul@example.com --select-only --yes
  [ "$status" -eq 0 ]
  grep -q '^git_email = "paul@example.com"$' "$CO/mise.local.toml"
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --select-only --yes
  [ "$status" -eq 0 ]
  grep -q '^git_email = "paul@example.com"$' "$CO/mise.local.toml"
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --git-email '' --select-only --yes
  [ "$status" -eq 0 ]
  ! grep -q '^git_email' "$CO/mise.local.toml" || false
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --git-email 'a"b@example.com' --select-only --yes
  [ "$status" -eq 2 ]
}
