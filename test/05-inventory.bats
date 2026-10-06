#!/usr/bin/env bats
# The declared inventory is well-formed and every Homebrew name is real. Read-only; needs the
# network for the Homebrew API and skips cleanly without it.
load helpers

all_package_keys() { cat "$REPO_ROOT"/mise*.toml | sed -n -E 's/^"([a-z-]+:[^"]+)".*/\1/p' | sort -u; }

@test "every declared package key names a manager this setup uses" {
  local key bad=()
  for key in $(all_package_keys); do
    case "$key" in brew:*|brew-cask:*|apt:*|mas:*) ;; *) bad+=("$key") ;; esac
  done
  [ ${#bad[@]} -eq 0 ] || { printf 'unexpected manager: %s\n' "${bad[@]}"; return 1; }
}

@test "every Homebrew formula and cask declared in the config exists in the Homebrew API" {
  command -v curl >/dev/null 2>&1 || skip "curl not available"
  curl -fsI --max-time 8 https://formulae.brew.sh/api/formula/jq.json >/dev/null 2>&1 || skip "no network access to formulae.brew.sh"
  local key kind name url bad=() n=0
  for key in $(all_package_keys | grep -E '^(brew|brew-cask):'); do
    kind=${key%%:*}; name=${key#*:}
    case "$name" in */*/*) continue ;; esac   # tap-qualified names have no API entry
    if [ "$kind" = brew ]; then url="https://formulae.brew.sh/api/formula/$name.json"; else url="https://formulae.brew.sh/api/cask/$name.json"; fi
    curl -fsI --max-time 15 "$url" >/dev/null 2>&1 || bad+=("$key")
    n=$((n + 1))
  done
  [ "$n" -gt 0 ]
  [ ${#bad[@]} -eq 0 ] || { printf 'not found in the Homebrew API: %s\n' "${bad[@]}"; return 1; }
}

@test "App Store apps are declared by numeric id, macOS only, in the desktop role file" {
  local line bad=()
  while IFS= read -r line; do
    [[ "$line" =~ ^\"mas:[0-9]+\" ]] && [[ "$line" == *'os = "macos"'* ]] || bad+=("$line")
  done < <(grep -h '^"mas:' "$REPO_ROOT"/mise*.toml || true)
  [ ${#bad[@]} -eq 0 ] || { printf 'bad mas entry: %s\n' "${bad[@]}"; return 1; }
  [ -z "$(grep -l '^"mas:' "$REPO_ROOT"/mise*.toml | grep -v 'mise.desktop.toml')" ]
}
