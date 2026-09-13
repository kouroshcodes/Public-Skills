#!/usr/bin/env bash
# Open one WezTerm tab per wave, each running its own Claude session.
# Usage: launch-waves.sh <chain-issue#> <first-wave> <last-wave> [repo-dir]
#        launch-waves.sh <chain-issue#> lead lead [repo-dir] [gen]  # successor lead (§L7), gen = 2, 3, ...
# Session names are fixed: wc<chain#>-wave<K>, wc<chain#>-lead, wc<chain#>-lead-<gen>.
# Tabs open in the WezTerm window this script runs in. Never Terminal.app.
# Wave sessions default to: --permission-mode auto --model sonnet --autocompact 600k
# Lead sessions default to: --permission-mode auto --model opus   --autocompact 450k
# Override with WAVE_CLAUDE_FLAGS / LEAD_CLAUDE_FLAGS.
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
if [ "$FROM" = lead ]; then
  pane=$(wezterm cli spawn --cwd "$REPO" -- zsh -lc \
    "$SCRUB exec claude --name wc$CHAIN-lead${GEN:+-$GEN} ${LEAD_CLAUDE_FLAGS:---permission-mode auto --model opus --autocompact 450k} '/wave-chain --implement'")
  wezterm cli set-tab-title --pane-id "$pane" "wc$CHAIN-lead${GEN:+-$GEN}" >/dev/null 2>&1 || true
  echo "lead wc$CHAIN-lead${GEN:+-$GEN} -> wezterm pane $pane"; exit 0
fi
for k in $(seq "$FROM" "$TO"); do
  pane=$(wezterm cli spawn --cwd "$REPO" -- zsh -lc \
    "$SCRUB exec claude --name wc$CHAIN-wave$k ${WAVE_CLAUDE_FLAGS:---permission-mode auto --model sonnet --autocompact 600k} '/wave-chain --implement $k'")
  wezterm cli set-tab-title --pane-id "$pane" "wc$CHAIN-wave$k" >/dev/null 2>&1 || true
  echo "wave $k wc$CHAIN-wave$k -> wezterm pane $pane"
done
