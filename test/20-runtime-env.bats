#!/usr/bin/env bats
# Gate 8: a mise-managed runtime (node) is available on every launch path, not only in an
# interactive terminal. Runs after 10-bootstrap.bats on the same machine.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
}

@test "node is on PATH in an interactive zsh" {
  run zsh -ic 'node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}

@test "node is on PATH in a login zsh" {
  run zsh -lc 'node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}

@test "node is on PATH in a non-interactive zsh started with an empty environment (the ssh/cron path)" {
  run env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c 'node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}

@test "node is on PATH over ssh to localhost when an ssh server is available" {
  ssh -o BatchMode=yes -o ConnectTimeout=3 localhost true 2>/dev/null || skip "no passwordless ssh to localhost here"
  run ssh -o BatchMode=yes localhost 'node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}
