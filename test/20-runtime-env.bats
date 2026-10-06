#!/usr/bin/env bats
# Gate 8 and the slice 3 runtime contract (plan.md §4.5): mise-managed runtimes resolve on every launch
# path, from the home directory and not only inside the checkout; nvm is retired; version files switch
# node; CLIs that used to pull Homebrew's node come from the npm backend. Runs after 10-bootstrap.bats.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
  cd "$HOME"
}

as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi; }
shims="$HOME/.local/share/mise/shims"

@test "node 24 resolves from the home directory in an interactive zsh" {
  run zsh -ic 'node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}

@test "node 24 resolves from the home directory in a login zsh" {
  run zsh -lc 'node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}

@test "node 24 resolves in a non-interactive zsh started with an empty environment (the ssh/cron path)" {
  run env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c 'cd && node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}

@test "a directory with .nvmrc switches node to that version, installing it when missing" {
  local d="$BATS_TEST_TMPDIR/project"
  mkdir -p "$d" && echo 22 > "$d/.nvmrc"
  run zsh -ic "cd '$d' && node -v"
  [ "$status" -eq 0 ]
  [[ "$output" == *v22.* ]]
}

@test "nvm is retired: no ~/.nvm, no nvm stub functions, no .nvm_setup link" {
  [ ! -d "$HOME/.nvm" ]
  [ ! -e "$HOME/.nvm_setup" ]
  run zsh -ic 'whence -w nvm node'
  [[ "$output" != *"nvm: function"* ]]
  [[ "$output" != *"node: function"* ]]
}

@test "agent-browser and gemini come from the npm backend, not from Homebrew's node" {
  run zsh -lc 'command -v agent-browser && command -v gemini'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.local/share/mise/"* ]]
  local prefix
  if is_macos; then prefix=/opt/homebrew; else prefix=/home/linuxbrew/.linuxbrew; fi
  [ ! -e "$prefix/opt/node" ]
}

@test "terraform and cargo resolve from the home directory" {
  run zsh -lc 'terraform version -json >/dev/null && cargo --version'
  [ "$status" -eq 0 ]
  [[ "$output" == cargo* ]]
}

@test "the default npm packages are installed alongside node" {
  run zsh -lc 'npm ls -g --depth=0 --json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.dependencies | has("task-master-ai") and has("@earendil-works/pi-coding-agent")'
}

@test "node resolves over ssh to localhost" {
  if ! ssh -o BatchMode=yes -o ConnectTimeout=3 localhost true 2>/dev/null; then
    arrange_sshd || skip "could not arrange an ssh server on this machine"
  fi
  run ssh -o BatchMode=yes localhost 'node -v'
  [ "$status" -eq 0 ]
  [[ "$output" == *v24.* ]]
}

# Start an ssh server that accepts this user's own key. Linux: openssh-server from apt (root or sudo);
# macOS: Remote Login via systemsetup (sudo). Best effort; the caller skips when it cannot be done.
arrange_sshd() {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  [ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
  grep -qsF "$(cat "$HOME/.ssh/id_ed25519.pub")" "$HOME/.ssh/authorized_keys" || cat "$HOME/.ssh/id_ed25519.pub" >> "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  ssh-keyscan -H localhost >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
  if is_linux; then
    command -v sshd >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive as_root apt-get install -y -qq openssh-server >/dev/null 2>&1 || return 1
    as_root ssh-keygen -A >/dev/null 2>&1 || true
    as_root mkdir -p /run/sshd
    pgrep -x sshd >/dev/null 2>&1 || as_root /usr/sbin/sshd 2>/dev/null || as_root systemctl start ssh 2>/dev/null || return 1
  else
    as_root systemsetup -setremotelogin on >/dev/null 2>&1 || return 1
  fi
  sleep 1
  ssh-keyscan -H localhost >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
  ssh -o BatchMode=yes -o ConnectTimeout=5 localhost true 2>/dev/null
}

@test "GUI applications see the mise shims on PATH (launchd on macOS, environment.d on Linux)" {
  if is_macos; then
    run launchctl getenv PATH
    [ "$status" -eq 0 ]
    [[ "$output" == *"$shims"* ]]
  else
    [ -f "$HOME/.config/environment.d/mise.conf" ]
    grep -q 'mise/shims' "$HOME/.config/environment.d/mise.conf"
    systemctl --user is-system-running >/dev/null 2>&1 || skip "no user systemd session here (container)"
    run systemd-run --user --pipe --quiet --wait sh -c 'echo "$PATH"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"mise/shims"* ]]
  fi
}

@test "agent-browser's Chromium is installed once, in Playwright's cache" {
  local cache
  if is_macos; then cache="$HOME/Library/Caches/ms-playwright"; else cache="$HOME/.cache/ms-playwright"; fi
  ls -d "$cache"/chromium* >/dev/null
}
