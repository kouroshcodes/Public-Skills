#!/usr/bin/env bash
# Open one WezTerm tab per wave, each running its own Claude session.
# Usage: launch-waves.sh <chain-issue#> <first-wave> <last-wave> [repo-dir]
#        launch-waves.sh <chain-issue#> lead lead [repo-dir] [gen]  # successor lead (§L7), gen = 2, 3, ...
# Session names are fixed: wc<chain#>-wave<K>, wc<chain#>-lead, wc<chain#>-lead-<gen>.
# Tabs open in the WezTerm window this script runs in. Never Terminal.app.
# Unattended tabs must never stop on a prompt. Verified 2026-09-13:
#   --permission-mode auto on Sonnet/Opus: "auto mode on", writes with no prompt -> works
#   --permission-mode auto on Haiku: silently falls back to manual mode and asks  -> stalls
#   --permission-mode bypassPermissions: one-time warning screen needing Enter   -> stalls
# So: auto mode, never Haiku for a session, plus --allowedTools as a safety net for
# anything auto mode would still pause on. --allowedTools must be in =value form:
# the space form swallows the prompt that follows it.
# Wave sessions: --model sonnet --autocompact 600k   Lead: --model opus --autocompact 450k
# Override with WAVE_CLAUDE_FLAGS / LEAD_CLAUDE_FLAGS.
ALLOW="--permission-mode auto --allowedTools=Bash,Edit,Write,MultiEdit,NotebookEdit,Agent,SendMessage,EnterWorktree,ExitWorktree,WebFetch,WebSearch"
set -euo pipefail
CHAIN=${1:?chain issue number}; FROM=${2:?first wave}; TO=${3:?last wave}
REPO=${4:-$PWD}; GEN=${5:-}
# The launcher runs INSIDE the lead's Claude session, so the tab would inherit the
# lead's CLAUDE_* environment: the child then takes the lead's name, is marked a
# child session, is hidden from ListAgents, and does not save its transcript.
# Verified 2026-09-13. Scrub it before exec.
SCRUB="unset \$(env | grep -o '^CLAUDE[A-Z0-9_]*' | tr '\n' ' ') 2>/dev/null;"
command -v wezterm >/dev/null || { echo "wezterm not on PATH" >&2; exit 1; }
wezterm cli list >/dev/null 2>&1 || { echo "not inside a WezTerm session - refusing to fall back to another terminal" >&2; exit 1; }
# Spawn into the window this script runs in - without --window-id wezterm opens a NEW window.
WIN=$(wezterm cli list --format json | jq -r --arg p "${WEZTERM_PANE:-x}" '.[] | select((.pane_id|tostring)==$p) | .window_id' | head -1)
[ -n "$WIN" ] || WIN=$(wezterm cli list --format json | jq -r '.[0].window_id')
SPAWN="wezterm cli spawn --window-id $WIN --cwd $REPO"
if [ "$FROM" = lead ]; then
  pane=$($SPAWN -- zsh -lc \
    "$SCRUB exec claude --name wc$CHAIN-lead${GEN:+-$GEN} ${LEAD_CLAUDE_FLAGS:-$ALLOW --model opus --autocompact 450k} '/wave-chain --implement'")
  wezterm cli set-tab-title --pane-id "$pane" "wc$CHAIN-lead${GEN:+-$GEN}" >/dev/null 2>&1 || true
  echo "lead wc$CHAIN-lead${GEN:+-$GEN} -> wezterm pane $pane"; exit 0
fi
for k in $(seq "$FROM" "$TO"); do
  pane=$($SPAWN -- zsh -lc \
    "$SCRUB exec claude --name wc$CHAIN-wave$k ${WAVE_CLAUDE_FLAGS:-$ALLOW --model sonnet --autocompact 600k} '/wave-chain --implement $k'")
  wezterm cli set-tab-title --pane-id "$pane" "wc$CHAIN-wave$k" >/dev/null 2>&1 || true
  echo "wave $k wc$CHAIN-wave$k -> wezterm pane $pane"
done
