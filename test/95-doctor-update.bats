#!/usr/bin/env bats
# Slice 9 on a converged machine: doctor passes (warnings allowed), update --dry-run changes nothing.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
  cd "$HOME"
}

@test "doctor passes on a converged machine (warnings allowed)" {
  run "$REPO_ROOT/tasks/doctor"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"drift"* ]]
  [[ "$output" == *"OK"*"login shell"* ]]
}

@test "update --dry-run on a converged machine leaves it converged" {
  run "$REPO_ROOT/tasks/update" --dry-run
  [ "$status" -eq 0 ]
  run "$REPO_ROOT/tasks/doctor"   # doctor's drift check knows which services a machine can manage
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"drift"* ]]
}
