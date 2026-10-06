#!/usr/bin/env bats
# Slice 5: AI tooling (plan.md §4.7). The public skills installer runs pinned to a reviewed release,
# herdr's agent integrations are installed, the CLIs come from the npm backend, and the settings
# merge keeps herdr's hook on a real machine. Runs after 10-bootstrap.bats.
load helpers

setup() {
  require_mutation
  [ -x "$HOME/.local/bin/mise" ] || skip "bootstrap has not run on this machine"
  cd "$HOME"
}

pinned_version() { sed -n -E 's/^claude_skills_version = "([^"]+)"$/\1/p' "$REPO_ROOT/mise.toml"; }

@test "the skills installer ran pinned to the declared release and left CLAUDE.md and the skills behind" {
  local v; v=$(pinned_version)
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ -f "$HOME/.claude/CLAUDE.md" ]
  [ -d "$HOME/.claude/skills/tdd" ]
  [ -d "$HOME/.claude/skills/testing" ]
  [ "$(cat "$HOME/.claude/.machine-setup-skills-version")" = "$v" ]
}

@test "running the skills task again at the same pin does nothing" {
  run bash -c "cd '$REPO_ROOT' && '$HOME/.local/bin/mise' run claude-skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at"* ]]
}

@test "claude and codex CLIs resolve from the home directory via mise, not Homebrew" {
  run zsh -lc 'command -v claude && command -v codex'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.local/share/mise/"* ]]
}

@test "herdr is installed and its Claude Code integration is in place" {
  run zsh -lc 'command -v herdr'
  [ "$status" -eq 0 ]
  run zsh -lc 'herdr integration status'
  [ "$status" -eq 0 ]
  [[ "$output" == *claude* ]]
}

@test "the settings merge kept herdr's hook alongside ours on a real machine" {
  jq -e '[.hooks.SessionStart[]?.hooks[]?.command] | any(test("herdr"))' "$HOME/.claude/settings.json"
  jq -e '[.hooks.PostToolUse[]?.hooks[]?.command] | any(test("prettier"))' "$HOME/.claude/settings.json"
}

@test "OpenCode configuration was installed" {
  [ -d "$HOME/.config/opencode" ]
}

@test "omp (Oh My Pi) is a mise tool from its GitHub releases and runs on this OS" {
  run zsh -lc 'command -v omp'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/mise/"* ]]
  run perl -e 'alarm shift; exec @ARGV' 30 zsh -lc 'omp --version'
  [ "$status" -eq 0 ]
}
