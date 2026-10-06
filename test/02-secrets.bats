#!/usr/bin/env bats
# Gate 4: locked 1Password handling. A fake `op` stands in for the 1Password CLI. Non-mutating
# (fresh HOME, private checkout copy). The mechanism has no production consumer since D6 chose OIDC
# for Conquer; the copy under test declares one so the behaviour stays proven.
load helpers

setup() {
  require_mise
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  # Declare conquer as needing 1Password in this copy only; the real list is empty since D6 (OIDC).
  sed -i.bak 's/^secret_envs = ""$/secret_envs = "conquer"/' "$CO/mise.toml" && rm -f "$CO/mise.toml.bak"
  grep -q '^secret_envs = "conquer"$' "$CO/mise.toml"
}

with_op() { export PATH="$FIXTURES/bin/op-$1:$PATH"; }

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


@test "with no secret-bearing envs declared, a locked 1Password changes nothing" {
  with_op locked
  sed -i.bak 's/^secret_envs = "conquer"$/secret_envs = ""/' "$CO/mise.toml" && rm -f "$CO/mise.toml.bak"
  run "$REPO_ROOT/bootstrap.sh" --dir "$CO" --profile personal --role conquer --machine studio --select-only --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"1Password"* ]]
  [ "$(env_list_of "$CO")" = "personal,conquer,machine-studio" ]
}
