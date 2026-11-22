#!/usr/bin/env bats
# Gates 2 and 3: dotfile-group composition across env files and machine-file discovery.
# Also: personal-only apps never appear in a work selection; removal lists compose across layers.
# Non-mutating: reads the effective configuration with a fresh HOME.
load helpers

setup() {
  require_jq
  require_mise
  fresh_home
  CO="$BATS_TEST_TMPDIR/checkout"
  copy_checkout "$CO"
  select_envs "$CO" personal desktop personal-macbook >/dev/null
}

# Group roots deployed for an env selection, as space-separated basenames.
groups_for() {
  (cd "$CO" && mise -E "$1" dot status --json 2>/dev/null | jq -r '.files[] | select(.mode == "symlink-each") | .source | split("/") | last' | sort | tr '\n' ' ' | sed 's/ $//')
}

# Every package name the effective configuration declares for an env selection.
packages_for() {
  (cd "$CO" && mise -E "$1" bootstrap packages status --json 2>/dev/null | jq -r '.. | objects | select(has("package")) | .package' | sort -u)
}

@test "the machine file is loaded by its env name, also when mise is invoked from outside the checkout" {
  run mise -C "$CO" -E personal,desktop,machine-personal-macbook config ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise/config.machine-personal-macbook.toml"* ]] || false
}

@test "the saved selection is honoured from inside the checkout" {
  run bash -c "cd '$CO' && '$(mise_bin)' config ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise/config.personal.toml"* ]] || false
  [[ "$output" == *"mise/config.desktop.toml"* ]] || false
  [[ "$output" == *"mise/config.machine-personal-macbook.toml"* ]] || false
}

@test "machine-personal-macbook deploys both the zsh and the ghostty groups" {
  [ "$(groups_for personal,desktop,machine-personal-macbook)" = "alacritty bin ghostty git gnupg herdr mise rex ssh tmux zellij zsh" ]
}

@test "the desktop role without a machine file still deploys zsh: group lists replace, so a role states the full list" {
  [ "$(groups_for personal,desktop)" = "alacritty bin ghostty git gnupg herdr mise rex ssh tmux zellij zsh" ]
}

@test "the work profile without roles deploys the base groups only (no ghostty, no rex)" {
  [ "$(groups_for work)" = "bin git gnupg herdr mise ssh tmux zellij zsh" ]
}

@test "every machine file yields a non-empty group list containing zsh" {
  local f env groups
  for f in "$CO"/mise/config.machine-*.toml; do
    env=$(basename "$f" .toml); env=${env#mise.}
    groups=$(groups_for "personal,$env")
    [[ " $groups " == *" zsh "* ]] || { echo "$env -> '$groups'"; return 1; }
  done
}

@test "a personal-only app is declared for personal and absent from work" {
  local app
  if is_macos; then app=spotify; else app=cmatrix; fi
  packages_for personal | grep -qx "$app"
  ! packages_for work | grep -qx "$app" || false
}

@test "the removal allowlist composes across the profile and machine layers" {
  run bash -c "cd '$CO' && '$(mise_bin)' -E work,machine-personal-macbook run remove-packages --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spotify"* && "$output" == *"discord"* && "$output" == *"jellyfin"* ]] || false
  [[ "$output" == *"cmatrix"* ]] || false
  run bash -c "cd '$CO' && '$(mise_bin)' -E personal,machine-personal-macbook run remove-packages --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" != *"spotify"* ]] || false
}

# Package keys declared in one layer file, e.g. brew-cask:spotify, apt:cmatrix.
declared_in() { sed -n -E 's/^"((brew|brew-cask|apt|mas):[^"]+)".*/\1/p' "$CO/$1"; }
name_of() { printf '%s' "$1" | cut -d: -f2-; }
removal_plan_for() { (cd "$CO" && mise -E "$1" run remove-packages --dry-run 2>/dev/null); }

@test "every package declared in the personal layer is absent from the work selection" {
  local work key name
  work=$(packages_for work)
  [ -n "$(declared_in mise/config.personal.toml)" ]
  for key in $(declared_in mise/config.personal.toml); do
    name=$(name_of "$key")
    if grep -qx "$name" <<<"$work"; then echo "$name is declared for personal but present in work"; return 1; fi
  done
}

@test "the work removal allowlist names every personal-only cask, so switching profile removes them" {
  local plan key name
  plan=$(removal_plan_for work,machine-personal-macbook)
  for key in $(declared_in mise/config.personal.toml | grep '^brew-cask:'); do
    name=$(name_of "$key")
    [[ "$plan" == *"$name"* ]] || { echo "$name is personal-only but not on the work removal allowlist"; return 1; }
  done
}

@test "the legacy unwanted packages stay on every profile's removal allowlist" {
  local env plan p
  for env in personal work; do
    plan=$(removal_plan_for "$env,machine-personal-macbook")
    for p in neofetch arc orbstack wezterm karabiner-elements; do
      [[ "$plan" == *"$p"* ]] || { echo "$p missing from the $env allowlist"; return 1; }
    done
  done
}

@test "work-only removals do not apply to the personal profile" {
  local plan; plan=$(removal_plan_for personal,machine-personal-macbook)
  [[ "$plan" != *"brave-browser"* ]] || false
  [[ "$plan" != *"protonvpn"* ]] || false
}

@test "the Linux desktop overlay declares the GUI set from the vendors' repositories for both profiles (D7)" {
  skip_unless_linux   # packages status lists only this OS's managers (no apt or flatpak entries on a Mac)
  local pk want; pk=$(packages_for personal,desktop,desktop-linux)
  for want in code cursor firefox brave-browser alacritty docker-ce docker-compose-plugin flatpak 1password-cli md.obsidian.Obsidian; do
    grep -qx "$want" <<<"$pk" || { echo "missing $want"; return 1; }
  done
  # 1Password's desktop app exists for x86_64 only; its arm64 repository ships the CLI alone.
  if [ "$(uname -m)" = x86_64 ]; then grep -qx 1password <<<"$pk"; else ! grep -qx 1password <<<"$pk"; fi
  pk=$(packages_for work,desktop,desktop-linux)
  grep -qx code <<<"$pk"
  ! grep -qx spotify <<<"$pk" || false
}

@test "every vendor apt key vendored under files/ is an ASCII-armored public key, so mise can deploy it (F-29)" {
  local k
  for k in "$CO"/files/*.asc; do
    head -1 "$k" | grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' || { echo "$k is not armored"; return 1; }
  done
}

@test "the machine files: personal-macbook and the test VMs state the full desktop group list, the CI runners the base list" {
  [ "$(groups_for personal,desktop,machine-personal-macbook)" = "alacritty bin ghostty git gnupg herdr mise rex ssh tmux zellij zsh" ]
  run mise -C "$CO" -E personal,desktop,machine-personal-macbook config ls
  [[ "$output" == *"mise/config.machine-personal-macbook.toml"* ]] || false
  [ "$(groups_for personal,desktop,machine-vm)" = "alacritty bin ghostty git gnupg herdr mise rex ssh tmux zellij zsh" ]
  [ "$(groups_for personal,machine-ci)" = "bin git gnupg herdr mise ssh tmux zellij zsh" ]
}

@test "on the test VMs' Linux, Ghostty launches with software rendering; nowhere else is it overridden (F-50)" {
  # The VM's virtual GPU offers OpenGL 4.1 and Ghostty needs 4.3, so it closed its window at once.
  local entry='~/.local/share/applications/com.mitchellh.ghostty.desktop'
  run bash -c "cd '$CO' && '$(mise_bin)' -E personal,desktop,desktop-linux,machine-vm,machine-vm-linux dot status --json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg t "$entry" '[.files[] | select(.target == $t)] | length == 1' >/dev/null
  grep -q 'Exec=env LIBGL_ALWAYS_SOFTWARE=1 ghostty' "$CO/mise/config.machine-vm-linux.toml"
  run bash -c "cd '$CO' && '$(mise_bin)' -E personal,desktop,desktop-linux,machine-personal-macbook dot status --json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg t "$entry" '[.files[] | select(.target == $t)] | length == 0' >/dev/null
}

@test "Slack is a desktop-role cask, not an App Store app, so a Mac that is not signed in still gets it (D-38)" {
  grep -q '^"brew-cask:slack" = { os = "macos" }' "$CO/mise/config.desktop.toml"
  ! grep -q '^"mas:803453959"' "$CO/mise/config.appstore.toml" || false   # Slack's App Store id
}

# The Dock list a file declares, as comma-separated app names.
dock_of() { sed -n '/^\[bootstrap.macos.dock\]/,/^\]/p' "$CO/$1" | sed -n 's|.*/\([^/]*\)\.app",.*|\1|p' | tr '\n' ','; }

@test "the Dock leads with Slack and pins Talat after FluidVoice, on the desktop role and on personal-macbook (D-38)" {
  [[ "$(dock_of mise/config.desktop-macos.toml)" == "Slack,Fantastical,"* ]] || false
  [[ "$(dock_of mise/config.desktop-macos.toml)" == *",FluidVoice,Talat,Obsidian," ]] || false
  [[ "$(dock_of mise/config.machine-personal-macbook.toml)" == "Slack,Spotify,Fantastical,"* ]] || false
  [[ "$(dock_of mise/config.machine-personal-macbook.toml)" == *",FluidVoice,Talat,Obsidian," ]] || false
}

@test "on a desktop Mac, Talat is installed in the post-dotfiles hook, before the Dock phase, and the login shell is still set (D-38)" {
  # Hooks replace per key across files (F-37), so the overlay must restate the base's login-shell hook.
  local hook; hook=$(sed -n '/^\[bootstrap.hooks\]/,/^$/p' "$CO/mise/config.desktop-macos.toml" | grep '^post-dotfiles')
  [[ "$hook" == *'"mise run login-shell"'*'"mise run talat"'* ]] || false
  grep -q '^post-dotfiles = "mise run login-shell"' "$CO/mise.toml"   # the base hook the overlay restates
}

@test "after macOS preferences and the Dock list are written, the Dock is restarted so it shows them, as Finder is (F-63)" {
  # The Dock reads its pinned apps only when it starts; without a restart a fresh install keeps showing Apple's set.
  local hook; hook=$(sed -n '/^\[bootstrap.hooks\]/,/^$/p' "$CO/mise/config.macos.toml" | grep '^post-defaults')
  [[ "$hook" == *'"chflags nohidden ~/Library"'* ]] || false
  [[ "$hook" == *'"killall Finder || true"'* ]] || false
  [[ "$hook" == *'"killall Dock || true"'* ]] || false
  # Hooks replace per key across files (F-37): a second post-defaults elsewhere would drop these commands.
  [ "$(grep -l '^post-defaults' "$CO"/mise.toml "$CO"/mise/config.*.toml)" = "$CO/mise/config.macos.toml" ]
}

@test "Cursor's own package never adds a second apt source: the pre-packages hook answers its question first (D-39)" {
  # Cursor's package would write cursor.sources with another key path beside the declared cursor.list,
  # and apt refuses a repository configured twice with different Signed-By values.
  local hook; hook=$(sed -n '/^\[bootstrap.hooks\]/,/^$/p' "$CO/mise/config.desktop-linux.toml" | grep '^pre-packages')
  [[ "$hook" == *'"mise run flathub"'* ]] || false
  [[ "$hook" == *'"mise run cursor-repo"'* ]] || false
  grep -q 'cursor/add-cursor-repo boolean false' "$CO/tasks/cursor-repo"
  grep -q 'signed-by=/etc/apt/keyrings/cursor.asc' "$CO/mise/config.desktop-linux.toml"
}
