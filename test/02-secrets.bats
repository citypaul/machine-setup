#!/usr/bin/env bats
# Gate 4: locked 1Password handling. A fake `op` stands in for the 1Password CLI and a fake
# `tailscale` records what it was asked to do. Non-mutating (fresh HOME, private checkout copy).
load helpers

setup() {
  require_mise
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  export FAKE_TAILSCALE_LOG="$BATS_TEST_TMPDIR/tailscale.log"
}

with_op() { export PATH="$FIXTURES/bin/op-$1:$FIXTURES/bin/tailscale-fake:$PATH"; }
canary() { printf 'CANARY-op-secret-7f3a9c'; }

@test "bootstrap drops the conquer env when 1Password is locked, says so, and remembers the role" {
  with_op locked
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"1Password"*"conquer"* ]]
  [ "$(env_list_of "$CO")" = "personal,machine-studio" ]
  grep -q '^roles = "conquer"$' "$CO/mise.local.toml"
}

@test "bootstrap keeps the conquer env when 1Password is signed in" {
  with_op unlocked
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [ "$(env_list_of "$CO")" = "personal,conquer,machine-studio" ]
}

@test "the join task reads the key at execution time, hands it to tailscale, and never prints or stores it" {
  with_op unlocked
  "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes >/dev/null
  run bash -c "cd '$CO' && '$(mise_bin)' run tailscale-join"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$(canary)"* ]]
  grep -q -- "--authkey $(canary)" "$FAKE_TAILSCALE_LOG"
  grep -q -- "--login-server https://" "$FAKE_TAILSCALE_LOG"
  # The checkout's own test dir holds the fake op and this file, both of which spell the canary.
  local leaked
  leaked=$(grep -rl --exclude-dir=test "$(canary)" "$HOME" "$CO" 2>/dev/null | grep -v -F "$FAKE_TAILSCALE_LOG" || true)
  [ -z "$leaked" ]
}

@test "a dry run with conquer selected never shows the secret" {
  with_op unlocked
  "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes >/dev/null
  run bash -c "cd '$CO' && '$(mise_bin)' bootstrap --dry-run"
  [[ "$output" != *"$(canary)"* ]]
  [[ "$output" == *"tailscale-join"* ]]
}

@test "the join task fails clearly when 1Password is locked and does not call tailscale" {
  with_op locked
  "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes >/dev/null
  run bash -c "cd '$CO' && '$(mise_bin)' -E personal,conquer,machine-studio run tailscale-join"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1Password"* ]]
  [ ! -e "$FAKE_TAILSCALE_LOG" ]
}
