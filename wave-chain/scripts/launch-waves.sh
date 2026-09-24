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
set -euo pipefail
CHAIN=${1:?chain issue number}; FROM=${2:?first wave}; TO=${3:?last wave}
REPO=${4:-$PWD}; GEN=${5:-}
# Workers branch into worktrees OUTSIDE the repo (this machine keeps them out of the tree
# the dev server watches). The session's first read inside its own worktree then trips
# "Allow reads outside the working directories?" - which --allowedTools does NOT cover,
# because that is a read-PATH prompt, not a tool prompt. Auto mode cannot clear it, so an
# unattended tab sits on it indefinitely. Verified 2026-09-16: a wave lost its whole run
# to this prompt while reporting nothing. --add-dir grants exactly the worktree parent.
# Override the location with WAVE_WORKTREE_DIR; default is <repo>-wt alongside the repo.
WORKTREE_DIR=${WAVE_WORKTREE_DIR:-${REPO%/}-wt}
ALLOW="--permission-mode auto --add-dir $WORKTREE_DIR --allowedTools=Bash,Edit,Write,MultiEdit,NotebookEdit,Agent,SendMessage,EnterWorktree,ExitWorktree,WebFetch,WebSearch"
command -v wezterm >/dev/null || { echo "wezterm not on PATH" >&2; exit 1; }
wezterm cli list >/dev/null 2>&1 || { echo "not inside a WezTerm session - refusing to fall back to another terminal" >&2; exit 1; }
# Spawn into the window this script runs in - without --window-id wezterm opens a NEW window.
WIN=$(wezterm cli list --format json | jq -r --arg p "${WEZTERM_PANE:-x}" '.[] | select((.pane_id|tostring)==$p) | .window_id' | head -1)
[ -n "$WIN" ] || WIN=$(wezterm cli list --format json | jq -r '.[0].window_id')

# The shell that hosts each tab. zsh where there is one (macOS, Linux); PowerShell
# on Windows, where there is no zsh and `wezterm cli spawn -- zsh` dies on spawn,
# taking the whole wave with it. Both are started as login/profile shells so a tab
# gets the same PATH the human would get by opening one by hand.
if command -v zsh >/dev/null 2>&1; then HOST=zsh
elif command -v pwsh >/dev/null 2>&1; then HOST=pwsh
else echo "neither zsh nor pwsh on PATH - nothing can host a wave tab" >&2; exit 1; fi

# spawn_tab <session-name> <claude-flags> <skill-arg>  -> prints the pane id
# The launcher runs INSIDE the lead's Claude session, so the tab would inherit the
# lead's CLAUDE_* environment: the child then takes the lead's name, is marked a
# child session, is hidden from ListAgents, and does not save its transcript.
# Verified 2026-09-13. Scrub it before the child starts, on both hosts.
spawn_tab() {
  local name="$1" flags="$2" arg="$3" pane
  if [ "$HOST" = zsh ]; then
    pane=$(wezterm cli spawn --window-id "$WIN" --cwd "$REPO" -- zsh -lc \
      "unset \$(env | grep -o '^CLAUDE[A-Z0-9_]*' | tr '\n' ' ') 2>/dev/null; exec claude --name $name $flags '$arg'")
  else
    pane=$(wezterm cli spawn --window-id "$WIN" --cwd "$REPO" -- pwsh -NoLogo -Command \
      "Get-ChildItem Env: | Where-Object Name -like 'CLAUDE*' | ForEach-Object { Remove-Item \"Env:\$(\$_.Name)\" -ErrorAction SilentlyContinue }; claude --name $name $flags '$arg'")
  fi
  wezterm cli set-tab-title --pane-id "$pane" "$name" >/dev/null 2>&1 || true
  echo "$pane"
}

if [ "$FROM" = lead ]; then
  name="wc$CHAIN-lead${GEN:+-$GEN}"
  pane=$(spawn_tab "$name" "${LEAD_CLAUDE_FLAGS:-$ALLOW --model opus --autocompact 450k}" "/wave-chain --implement --chain $CHAIN")
  echo "lead $name -> wezterm pane $pane"; exit 0
fi
for k in $(seq "$FROM" "$TO"); do
  name="wc$CHAIN-wave$k"
  pane=$(spawn_tab "$name" "${WAVE_CLAUDE_FLAGS:-$ALLOW --model sonnet --autocompact 600k}" "/wave-chain --implement $k --chain $CHAIN")
  echo "wave $k $name -> wezterm pane $pane"
done
