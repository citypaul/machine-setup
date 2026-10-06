#!/usr/bin/env bats
# Slice 4: the Conquer role installs the Tailscale client and joins the Headscale network by OIDC
# browser login (plan D6). The join itself needs a person in a browser, so the automated evidence
# is: client installed and its daemon running, the join task prints the login URL (or says it is
# already connected), and it never stores a key. Runs after 10-bootstrap.bats with the role added.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
}

@test "adding the conquer role converges and installs the Tailscale client" {
  run "$REPO_ROOT/bootstrap.sh" --dir "$REPO_ROOT" --role desktop,conquer --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *",conquer,"* ]]
  run zsh -lc 'tailscale version'
  [ "$status" -eq 0 ]
}

@test "the Tailscale daemon is running (Linux)" {
  skip_unless_linux
  run systemctl is-active tailscaled
  [ "$output" = "active" ]
}

@test "the Tailscale app is installed and its CLI linked (macOS)" {
  skip_unless_macos
  [ -d /Applications/Tailscale.app ]
  grep -q '/Applications/Tailscale.app/Contents/MacOS/Tailscale' "$HOME/.local/bin/tailscale"
  [ -x "$HOME/.local/bin/tailscale" ]
}

@test "the join task is a no-op when already connected" {
  export PATH="$FIXTURES/bin/tailscale-connected:$PATH"
  run bash -c "cd '$REPO_ROOT' && '$HOME/.local/bin/mise' run tailscale-join"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already connected"* ]]
}

@test "the join task prints the OIDC login URL and stops when the network needs a login" {
  export PATH="$FIXTURES/bin/tailscale-needs-login:$PATH"
  run bash -c "cd '$REPO_ROOT' && '$HOME/.local/bin/mise' run tailscale-join"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://login.example/register/abc"* ]]
  [[ "$output" == *"--login-server https://"* ]]
}
