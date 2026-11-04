#!/usr/bin/env bats
# The Herdr desktop app (herdr.dev), beside the herdr CLI from Homebrew. tasks/herdr-app installs it
# once with the desktop role, from the release feed the app updates itself from, and refuses a
# download whose checksum or (on macOS) Developer ID signature is wrong. Pure: fresh HOME, and a
# release feed on disk through HERDR_RELEASES_URL, the override the vendor's own installer reads.
load helpers

setup() {
  fresh_home
  FEED="$BATS_TEST_TMPDIR/feed"
  mkdir -p "$FEED/app"
  export HERDR_RELEASES_URL="file://$FEED"
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) TARGET=linux-x86_64 ;;
    Linux-aarch64) TARGET=linux-aarch64 ;;
    Darwin-arm64) TARGET=macos-aarch64 ;;
    *) skip "Herdr has no build for $(uname -s) $(uname -m)" ;;
  esac
}

sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# Publish a release to the fake feed, laid out the way releases.herdr.dev lays out its tarballs:
# herdr-app/ (the program and its icon) on Linux, Herdr.app on macOS. Optional: a sha256 to publish
# instead of the real one.
publish_release() {
  local stage="$BATS_TEST_TMPDIR/stage" sum
  mkdir -p "$stage"
  if is_linux; then
    mkdir -p "$stage/herdr-app"
    printf '#!/bin/sh\necho herdr-app-fixture\n' > "$stage/herdr-app/herdr-app"
    chmod +x "$stage/herdr-app/herdr-app"
    echo '<svg xmlns="http://www.w3.org/2000/svg"/>' > "$stage/herdr-app/herdr-app.svg"
    tar -czf "$FEED/app/app.tar.gz" -C "$stage" herdr-app
  else
    mkdir -p "$stage/Herdr.app/Contents/MacOS"
    printf '#!/bin/sh\necho herdr-app-fixture\n' > "$stage/Herdr.app/Contents/MacOS/Herdr"
    chmod +x "$stage/Herdr.app/Contents/MacOS/Herdr"
    tar -czf "$FEED/app/app.tar.gz" -C "$stage" Herdr.app
  fi
  sum=${1:-$(sha256_of "$FEED/app/app.tar.gz")}
  cat > "$FEED/app/latest.json" <<EOF
{
  "version": "9.9.9",
  "targets": {
    "$TARGET": {
      "url": "file://$FEED/app/app.tar.gz",
      "sha256": "$sum"
    }
  }
}
EOF
}

app_path() { if is_linux; then echo "$HOME/.local/share/herdr-app"; else echo "$HOME/Applications/Herdr.app"; fi; }

@test "the herdr-app task does nothing without the desktop role" {
  publish_release
  run "$REPO_ROOT/tasks/herdr-app" "personal"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]] || false
  [ ! -e "$(app_path)" ]
}

@test "on Linux it installs the app, a herdr-app command and a launcher entry, leaving the herdr CLI alone" {
  skip_unless_linux
  publish_release
  run "$REPO_ROOT/tasks/herdr-app" "desktop"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/share/herdr-app/herdr-app" ]
  [ "$("$HOME/.local/bin/herdr-app")" = herdr-app-fixture ]
  grep -qx "Exec=$HOME/.local/bin/herdr-app" "$HOME/.local/share/applications/herdr-app.desktop"
  [ -f "$HOME/.local/share/icons/hicolor/scalable/apps/herdr-app.svg" ]
  [ ! -e "$HOME/.local/bin/herdr" ]
}

@test "a download whose checksum does not match the feed is refused and nothing is installed" {
  publish_release 0000000000000000000000000000000000000000000000000000000000000000
  run "$REPO_ROOT/tasks/herdr-app" "desktop"
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum"* ]] || false
  [ ! -e "$(app_path)" ]
  [ ! -e "$HOME/.local/bin/herdr-app" ]
}

@test "on macOS an app not signed by Herdr's Developer ID is refused and nothing is installed" {
  skip_unless_macos
  publish_release
  run "$REPO_ROOT/tasks/herdr-app" "desktop"
  [ "$status" -ne 0 ]
  [[ "$output" == *"signed"* ]] || false
  [ ! -e "$HOME/Applications/Herdr.app" ]
}

@test "an installed app is left to update itself: the feed is not read again" {
  mkdir -p "$(app_path)"
  run "$REPO_ROOT/tasks/herdr-app" "desktop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]] || false
}

@test "an unreachable release feed is a warning, not a failed bootstrap" {
  run "$REPO_ROOT/tasks/herdr-app" "desktop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"re-run 'mise run herdr-app'"* ]] || false
  [ ! -e "$(app_path)" ]
}
