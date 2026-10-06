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

@test "the old pnpm globals are installed as mise tools" {
  run bash -c "cd && '$HOME/.local/bin/mise' ls --installed --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("npm:task-master-ai") and has("npm:@earendil-works/pi-coding-agent")'
}

@test "the login shell is zsh, so ssh and cron shells read .zshenv and .zprofile" {
  # Run the task here too so its output is visible on failure (bats hides it inside bootstrap).
  run bash -c "cd '$REPO_ROOT' && '$HOME/.local/bin/mise' run login-shell"
  [ "$status" -eq 0 ]
  local user shell; user=$(id -un)
  if is_macos; then shell=$(dscl . -read "/Users/$user" UserShell | awk '{print $2}'); else shell=$(getent passwd "$user" | cut -d: -f7); fi
  [[ "$shell" == */zsh ]] || { echo "login shell is $shell; task said: $output"; return 1; }
}

@test "brewed CLI tools resolve in login and interactive zsh without a brew binary on PATH" {
  run zsh -lc 'command -v rg gh'
  [ "$status" -eq 0 ]
  run zsh -ic 'command -v rg gh'
  [ "$status" -eq 0 ]
  run env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c 'cd && command -v rg'
  [ "$status" -eq 0 ]
}

@test "mise-poured TLS clients in the Homebrew prefix can verify certificates" {
  local prefix
  if is_macos; then prefix=/opt/homebrew; else prefix=/home/linuxbrew/.linuxbrew; fi
  # curl is keg-only on macOS (provided by the OS), so probe wget there; both link brewed OpenSSL.
  if [ -x "$prefix/bin/curl" ]; then
    run "$prefix/bin/curl" -fsS -o /dev/null -w '%{http_code}' https://github.com
    [ "$status" -eq 0 ] && [ "$output" = "200" ]
  elif [ -x "$prefix/bin/wget" ]; then
    run "$prefix/bin/wget" -q --spider https://github.com
    [ "$status" -eq 0 ]
  else
    skip "no brewed TLS client linked in $prefix/bin"
  fi
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
    systemctl --user show-environment >/dev/null 2>&1 || skip "no user systemd session here (container)"
    # environment.d applies at the next login; the session-path hook covers the running session.
    run systemctl --user show-environment
    [[ "$output" == *"mise/shims"* ]]
  fi
}

@test "agent-browser's browser is installed where Chrome for Testing supports the platform, and the task is idempotent" {
  run bash -c "cd '$REPO_ROOT' && '$HOME/.local/bin/mise' run install-browsers"
  [ "$status" -eq 0 ]
  if [[ "$output" == *"unsupported here"* ]]; then skip "no Chrome for Testing build for this platform"; fi
  [[ "$output" != *"warning:"* ]]
  # agent-browser names its own cache; the observable contract is that a second run finds the browser.
  run bash -c "cd '$REPO_ROOT' && '$HOME/.local/bin/mise' run install-browsers"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* ]]
}

@test "fzf key bindings and zsh-autosuggestions load in an interactive zsh (slice 7)" {
  run zsh -ic 'bindkey'
  [ "$status" -eq 0 ]
  [[ "$output" == *"fzf-history-widget"* ]]
  run zsh -ic 'typeset -f _zsh_autosuggest_start >/dev/null && echo loaded'
  [[ "$output" == *"loaded"* ]]
}

@test "Oh My Zsh, the NvChad config and neovim are present (declared repos and a formula)" {
  [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]
  [ -f "$HOME/.config/nvim/init.lua" ]
  [ "$(git -C "$HOME/.config/nvim" branch --show-current)" = "v2.0" ]
  run zsh -lc 'nvim --version'
  [ "$status" -eq 0 ]
  [[ "$output" == NVIM* ]]
}

@test "tmux, zellij and herdr configs are linked from their groups" {
  [ "$(readlink "$HOME/.tmux.conf")" = "$REPO_ROOT/tmux/.tmux.conf" ]
  [ "$(readlink "$HOME/.config/zellij/config.kdl")" = "$REPO_ROOT/zellij/.config/zellij/config.kdl" ]
  [ "$(readlink "$HOME/.config/herdr/config.toml")" = "$REPO_ROOT/herdr/.config/herdr/config.toml" ]
}

@test "the gh-extensions task installs gh-stack when gh is signed in and otherwise says what to run" {
  run mise_in_checkout run gh-extensions
  [ "$status" -eq 0 ]
  if zsh -lc 'gh auth status' >/dev/null 2>&1; then
    run zsh -lc 'gh extension list'
    [[ "$output" == *"gh-stack"* ]]
  else
    [[ "$output" == *"gh auth login"* ]]
  fi
}
