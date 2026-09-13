#!/usr/bin/env bash
# Open one WezTerm tab per wave, each running its own Claude session.
# Usage: launch-waves.sh <chain-issue#> <first-wave> <last-wave> [repo-dir]
# Tabs open in the WezTerm window this script runs in. Never Terminal.app.
# Child sessions default to: --permission-mode auto --model sonnet.
# Override with
# WAVE_CLAUDE_FLAGS, e.g. WAVE_CLAUDE_FLAGS="--permission-mode auto --model opus".
set -euo pipefail
CHAIN=${1:?chain issue number}; FROM=${2:?first wave}; TO=${3:?last wave}
REPO=${4:-$PWD}
command -v wezterm >/dev/null || { echo "wezterm not on PATH" >&2; exit 1; }
wezterm cli list >/dev/null 2>&1 || { echo "not inside a WezTerm session - refusing to fall back to another terminal" >&2; exit 1; }
for k in $(seq "$FROM" "$TO"); do
  pane=$(wezterm cli spawn --cwd "$REPO" -- zsh -lc \
    "exec claude ${WAVE_CLAUDE_FLAGS:---permission-mode auto --model sonnet} '/wave-chain --implement $k'")
  wezterm cli set-tab-title --pane-id "$pane" "wave $k" >/dev/null 2>&1 || true
  echo "wave $k -> wezterm pane $pane"
done
