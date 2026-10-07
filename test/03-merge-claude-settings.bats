#!/usr/bin/env bats
# Gate 6: ~/.claude/settings.json is produced by an atomic semantic merge that preserves keys and
# hooks we do not own (herdr's SessionStart hook included). Pure: fresh HOME, no mise needed.
load helpers

setup() {
  require_jq
  fresh_home
  mkdir -p "$HOME/.claude"
  TARGET="$HOME/.claude/settings.json"
  MERGE=("$REPO_ROOT/tasks/merge-claude-settings" --source "$REPO_ROOT/claude/settings.json" --target "$TARGET")
}

hook_commands() { jq -r ".hooks.$1[].hooks[].command" "$TARGET"; }

@test "creates the file from the repo settings when none exists" {
  run "${MERGE[@]}"
  [ "$status" -eq 0 ]
  jq -e '.model == "opus"' "$TARGET"
  jq -e '.alwaysThinkingEnabled == true' "$TARGET"
  hook_commands PostToolUse | grep -q prettier
}

@test "preserves unknown keys and existing hooks, including herdr's SessionStart hook" {
  cp "$FIXTURES/claude-settings/existing-with-herdr.json" "$TARGET"
  run "${MERGE[@]}"
  [ "$status" -eq 0 ]
  jq -e '.customKey == "keep-me"' "$TARGET"
  hook_commands SessionStart | grep -q herdr-agent-state
  hook_commands PostToolUse | grep -q unrelated-hook
  hook_commands PostToolUse | grep -q prettier
}

@test "owned scalar keys take the repo value" {
  cp "$FIXTURES/claude-settings/existing-with-herdr.json" "$TARGET"
  "${MERGE[@]}"
  jq -e '.model == "opus"' "$TARGET"
}

@test "applying twice yields byte-identical output and no duplicate hooks" {
  cp "$FIXTURES/claude-settings/existing-with-herdr.json" "$TARGET"
  "${MERGE[@]}"
  cp "$TARGET" "$BATS_TEST_TMPDIR/first.json"
  "${MERGE[@]}"
  cmp -s "$TARGET" "$BATS_TEST_TMPDIR/first.json"
  [ "$(hook_commands PostToolUse | grep -c prettier)" -eq 1 ]
  [ "$(hook_commands SessionStart | grep -c herdr)" -eq 1 ]
}

@test "a malformed settings file is left byte-for-byte untouched and the merge fails" {
  printf '{ "model": "opus", \n' > "$TARGET"
  cp "$TARGET" "$BATS_TEST_TMPDIR/before.json"
  run "${MERGE[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"settings.json"* ]] || false
  cmp -s "$TARGET" "$BATS_TEST_TMPDIR/before.json"
  [ -z "$(find "$HOME/.claude" -name '*.tmp*' -o -name '.settings*' | head -1)" ]
}

@test "the result is valid JSON that Claude Code can read (object at the root)" {
  cp "$FIXTURES/claude-settings/existing-with-herdr.json" "$TARGET"
  "${MERGE[@]}"
  jq -e 'type == "object"' "$TARGET"
}
