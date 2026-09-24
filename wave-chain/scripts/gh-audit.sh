#!/usr/bin/env bash
# Verify that GitHub reflects the run. Exit 1 on any FAIL.
# Usage: gh-audit.sh <chain-issue#>          whole chain (lead, before finishing)
#        gh-audit.sh <chain-issue#> <wave K> one wave (orchestrator, before its landed line)
# Checks the state of things, never an agent's claim about them.
set -uo pipefail
CHAIN=${1:?chain issue number}; WAVE=${2:-}
BRANCH="wave-chain/$CHAIN"
fail=0; F(){ echo "FAIL  $*"; fail=1; }; OK(){ echo "ok    $*"; }

since=$(gh issue view "$CHAIN" --json createdAt --jq .createdAt)
# Chain membership (SKILL.md "Several chains"): tickets labelled chain:<CHAIN>; a legacy
# chain (none of its tickets labelled) is the wave:* tickets that carry no chain:* label.
if [ -n "$(gh issue list --state all --label "chain:$CHAIN" --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null)" ]; then
  member="any(.labels[].name; . == \"chain:$CHAIN\")"
else
  member="all(.labels[].name; startswith(\"chain:\") | not)"
fi
sel='.labels[].name | select(startswith("wave:"))'
[ -n "$WAVE" ] && sel="(.labels[].name | select(. == \"wave:$WAVE\"))"

gh issue list --state all --limit 300 \
  --json number,state,closedAt,labels,assignees,comments \
  --jq ".[] | select(any($sel; true)) | select($member) | select(.state == \"OPEN\" or (.closedAt // \"\") > \"$since\") | select(all(.labels[].name; . != \"hitl\")) |
        {n:.number, s:.state, ip:(any(.labels[].name; . == \"in-progress\")),
         last:(.comments | sort_by(.createdAt) | last | {b:.body, t:.createdAt}),
         run:([.comments[] | select(.createdAt > \"$since\") | .body] | join(\"\\n\"))}" \
| while IFS= read -r row; do
  n=$(jq -r .n <<<"$row"); st=$(jq -r .s <<<"$row"); ip=$(jq -r .ip <<<"$row")
  body=$(jq -r '.run // ""' <<<"$row"); t=$(jq -r '.last.t // ""' <<<"$row")
  if [ "$st" = "OPEN" ] && [ "$ip" = "true" ]; then F "#$n open and still in-progress"; continue; fi
  if [ "$st" = "CLOSED" ]; then
    grep -Eq 'pull/[0-9]+' <<<"$body" && grep -Eiq 'done when|evidence|[a-z0-9_./-]+:[0-9]+' <<<"$body" \
      && OK "#$n closed with PR + evidence" || F "#$n closed but no comment this run carries a PR link and file:line evidence"
    continue
  fi
  if [ "$st" = "OPEN" ]; then
    [[ "$t" > "$since" ]] && OK "#$n open, commented this run" || F "#$n open with no comment since the chain started (why did it not land?)"
  fi
done | tee /tmp/gh-audit.$$ ; grep -q '^FAIL' /tmp/gh-audit.$$ && fail=1

# wave PRs against the chain branch
prs=$(gh pr list --state all --base "$BRANCH" --limit 100 --json number,state,title,isDraft)
if [ -n "$WAVE" ]; then prs=$(jq "[.[] | select(.title | test(\"^wave $WAVE:\"))]" <<<"$prs"); fi
jq -r '.[] | "\(.number)\t\(.state)\t\(.isDraft)\t\(.title)"' <<<"$prs" | while IFS=$'\t' read -r n st d ti; do
  [ "$st" = "MERGED" ] && OK "PR #$n merged into $BRANCH" || F "PR #$n ($ti) is $st, not merged into $BRANCH"
done | tee -a /tmp/gh-audit.$$ ; grep -q '^FAIL' /tmp/gh-audit.$$ && fail=1
[ -n "$WAVE" ] && [ "$(jq length <<<"$prs")" = 0 ] && { F "no PR titled 'wave $WAVE:' against $BRANCH"; }

# chain PR, whole-chain audit only
if [ -z "$WAVE" ]; then
  cp=$(gh pr list --state all --head "$BRANCH" --limit 1 --json number,isDraft,body)
  if [ "$(jq length <<<"$cp")" = 0 ]; then F "no chain PR from $BRANCH"; else
    [ "$(jq -r '.[0].isDraft' <<<"$cp")" = "false" ] && OK "chain PR ready for review" || F "chain PR #$(jq -r '.[0].number' <<<"$cp") is still a draft"
    cbody=$(jq -r '.[0].body' <<<"$cp")
    gh issue list --state closed --limit 300 --json number,labels,closedAt \
      --jq ".[] | select(any(.labels[].name; startswith(\"wave:\"))) | select($member) | select((.closedAt // \"\") > \"$since\") | .number" | while read -r n; do
      grep -q "\[x\] #$n\b" <<<"$cbody" || F "chain PR body does not tick #$n"
    done | tee -a /tmp/gh-audit.$$ ; grep -q '^FAIL' /tmp/gh-audit.$$ && fail=1
  fi
fi
rm -f /tmp/gh-audit.$$
[ "$fail" = 0 ] && echo "AUDIT PASS" || { echo "AUDIT FAIL - fix every FAIL line on GitHub, then rerun"; exit 1; }
