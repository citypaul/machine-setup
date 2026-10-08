#!/usr/bin/env bats
# Slice 8: the Linux desktop set (plan D7). With the desktop role, the GUI apps come from the vendors'
# apt repositories whose keys are vendored in the repo, Alacritty from Ubuntu, Ghostty from the
# ghostty-ubuntu builds, Obsidian as a Flatpak, and Docker runs with the user in its group. Runs after
# 60-conquer.bats, which adds the desktop role on the test machines.
load helpers

setup() {
  require_mutation
  skip_unless_linux
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
  grep -q '^roles = ".*desktop' "$REPO_ROOT/mise.local.toml" || skip "desktop role not selected on this machine"
  cd "$HOME"
}

@test "1Password, VS Code and Brave come from their vendors' apt repositories" {
  run zsh -lc 'command -v code brave-browser op'
  [ "$status" -eq 0 ]
  apt-cache policy code | grep -q 'packages.microsoft.com'
  apt-cache policy 1password-cli | grep -q 'downloads.1password.com'
  apt-cache policy brave-browser | grep -q 'brave-browser-apt-release'
  if [ "$(uname -m)" = x86_64 ]; then
    run zsh -lc 'command -v 1password'
    [ "$status" -eq 0 ]
  else
    ! dpkg -s 1password >/dev/null 2>&1 || false   # no arm64 build of the desktop app (D-30)
  fi
}

@test "Alacritty is installed from Ubuntu and Ghostty from the ghostty-ubuntu build for this release" {
  run zsh -lc 'command -v alacritty'
  [ "$status" -eq 0 ]
  dpkg -s ghostty >/dev/null 2>&1 || { echo "ghostty not installed: $(mise_in_checkout run ghostty-linux 2>&1 | tail -3)"; return 1; }
  run zsh -lc 'command -v ghostty'
  [ "$status" -eq 0 ]
  run mise_in_checkout run ghostty-linux
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]] || false
}

@test "the terminals use the Linux font sizes, which look like the Mac's (Linux counts 96 dots per inch, macOS 72)" {
  # Paul's first run by hand: the Mac sizes made the Ubuntu VM's terminals a third larger (ADR 0001 F-58).
  run zsh -lc 'ghostty +show-config'
  [ "$status" -eq 0 ]
  grep -q -x 'font-size = 13.5' <<<"$output"
  [ "$(sed -n 's/^size = //p' "$HOME/.config/alacritty/font-size.toml")" = 14 ]
  ! grep -q -E '^[[:space:]]*size[[:space:]]*=' "$HOME/.alacritty.toml" || false   # the import must win
}

@test "Docker Engine is installed, its daemon runs where systemd does, and the user is in the docker group" {
  run zsh -lc 'command -v docker'
  [ "$status" -eq 0 ]
  docker compose version >/dev/null
  getent group docker | grep -q "\b$(id -un)\b"
  if [ -d /run/systemd/system ]; then
    [ "$(systemctl is-active docker)" = active ]
  fi
}

@test "Obsidian is installed as a per-user Flatpak from Flathub" {
  flatpak remotes --user | grep -q flathub
  flatpak list --user --app --columns=application | grep -qx 'md.obsidian.Obsidian'
}

@test "the converged Linux desktop reports no drift" {
  run mise_in_checkout bootstrap status --missing
  [ "$status" -eq 0 ]
}
