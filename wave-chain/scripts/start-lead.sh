#!/usr/bin/env bash
# Start the wave-chain lead in THIS tab, correctly named and capped, with nothing to type.
# Usage: start-lead.sh [chain-issue#]   (run from inside the repo)
# With no number it uses the one open chain issue; with several open it lists them and
# refuses to guess (SKILL.md "Several chains").
set -euo pipefail
CHAIN=${1:-}
if [ -z "$CHAIN" ]; then
  OPEN=$(gh issue list --label orchestrator --state open --limit 20 --json number,title --jq '.[] | "\(.number)\t\(.title)"')
  [ -n "$OPEN" ] || { echo "no open chain issue (label: orchestrator) - run /wave-chain --modify first" >&2; exit 1; }
  if [ "$(printf '%s\n' "$OPEN" | wc -l | tr -d ' ')" -gt 1 ]; then
    echo "several chains are open - name one: wave-chain <chain#>" >&2; printf '%s\n' "$OPEN" >&2; exit 1
  fi
  CHAIN=$(printf '%s\n' "$OPEN" | cut -f1)
fi
ALLOW="--permission-mode auto --allowedTools=Bash,Edit,Write,MultiEdit,NotebookEdit,Agent,SendMessage,EnterWorktree,ExitWorktree,WebFetch,WebSearch"
exec claude --name "wc$CHAIN-lead" ${LEAD_CLAUDE_FLAGS:-$ALLOW --model opus --autocompact 450k} "/wave-chain --implement --chain $CHAIN"
