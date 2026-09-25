#!/usr/bin/env bash
# Compute one wave's frontier from GitHub, so no session computes it by hand (SKILL.md §I1).
# Usage: frontier.sh <chain-issue#> <wave K>
# Prints, per open unassigned non-hitl ticket in the wave:
#   runnable #n                     no open blocker - claim it
#   blocked  #n  on #a #b           leave it; it frees when those close
# and "  waited on by #x #y" under a ticket that other open tickets need (who you owe a release).
set -euo pipefail
CHAIN=${1:?chain issue number}; K=${2:?wave number}
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
# Chain membership (SKILL.md "Several chains"); a legacy chain has no chain:* labels.
if [ -n "$(gh issue list --state all --label "chain:$CHAIN" --limit 1 --json number --jq '.[0].number // empty')" ]; then
  labels=(--label "chain:$CHAIN" --label "wave:$K"); member='.'
else
  labels=(--label "wave:$K"); member='select(all(.labels[].name; startswith("chain:") | not))'
fi
gh issue list --state open --limit 300 "${labels[@]}" --json number,assignees,labels \
  --jq ".[] | $member | select((.assignees | length) == 0) | select(all(.labels[].name; . != \"hitl\")) | .number" |
while read -r n; do
  on=$(gh api "repos/$REPO/issues/$n/dependencies/blocked_by" --jq '[.[] | select(.state == "open") | "#\(.number)"] | join(" ")')
  if [ -z "$on" ]; then echo "runnable #$n"; else echo "blocked  #$n  on $on"; fi
  by=$(gh api "repos/$REPO/issues/$n/dependencies/blocking" --jq '[.[] | select(.state == "open") | "#\(.number)"] | join(" ")' 2>/dev/null || true)
  if [ -n "$by" ]; then echo "  waited on by $by"; fi
done
exit 0
