#!/usr/bin/env bash
# Start the wave-chain lead in THIS tab, correctly named and capped, with nothing to type.
# Usage: start-lead.sh   (run from inside the repo; finds the open chain issue itself)
set -euo pipefail
CHAIN=$(gh issue list --label orchestrator --state open --limit 1 --json number --jq '.[0].number // empty')
[ -n "$CHAIN" ] || { echo "no open chain issue (label: orchestrator) - run /wave-chain --modify first" >&2; exit 1; }
ALLOW="--permission-mode acceptEdits --allowedTools=Bash,Edit,Write,MultiEdit,NotebookEdit,Agent,SendMessage,EnterWorktree,ExitWorktree,WebFetch,WebSearch"
exec claude --name "wc$CHAIN-lead" ${LEAD_CLAUDE_FLAGS:-$ALLOW --model opus --autocompact 450k} '/wave-chain --implement'
