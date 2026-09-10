---
name: wave-chain
description: Use when GitHub issues must be handed to several orchestrator sessions at once, one wave each, running in parallel and unblocking each other by message. Triggers on "GH Issue #N, Wave K", on asking how many waves there are, on a ticket that must wait for another session's ticket to land, and on a hitl ticket that is stalling someone else's work. [kourosh]
argument-hint: "nothing (build the chain) | a wave number, e.g. 3 (run that wave)"
metadata:
  author: kourosh
---

N orchestrators start at the **same time**, one per wave, all pointed at one chain issue. Waves decide who owns which tickets. They are not barriers, and no wave waits for another wave as a unit.

**The lock is per ticket, and it is queryable.** GitHub's native `blockedBy` edges are the only lock. Never a status column, never prose in a body, never a guess. An orchestrator that finds one of its tickets blocked leaves that ticket and runs its others — it does not idle a whole wave over one edge.

**Release is a push.** The orchestrator that closes a blocker messages whoever was waiting. Nobody polls.

If the project has a build/orchestration protocol doc (here, `docs/agents/build-waves.md`), it is the authority on how a single wave is run. This skill is the protocol *between* orchestrators. Where they disagree, that doc wins.

Pick a mode by the argument:

| Argument | Mode |
|---|---|
| none | **§A** — build the chain issue |
| a wave number, or "GH Issue #N, Wave K" | **§B** — run wave K |

---

# §A Build the chain

## A1. Read the real issues

```bash
gh issue list --state open --limit 300 --json number,title,labels,url
```

Never restate a ticket from memory. If `wave:*` labels exist they **are** the plan — group by them, do not re-cut. Only unlabelled tickets need placing.

Carve out what is not agent work: `hitl` (the owner's, never claimed by an agent), dated tickets, and the `wayfinder:map` ticket. List them separately.

## A2. Make every dependency a real edge

A dependency that lives only in prose cannot be queried, so an agent guesses. Convert each one:

```bash
BLOCKER_ID=$(gh api repos/{owner}/{repo}/issues/<blocker> --jq .id)
gh api -X POST repos/{owner}/{repo}/issues/<blocked>/dependencies/blocked_by -F issue_id=$BLOCKER_ID
```

The endpoint takes the blocker's **internal REST `id`**, not its issue number — passing the number silently points the edge at the wrong ticket. Verify every edge afterwards with the read query in §B1.

## A3. Write the chain issue

Fill [`references/chain-issue.md`](references/chain-issue.md), then:

```bash
gh issue create --title "Wave chain — <YYYY-MM-DD>" --label orchestrator --body-file <path>
```

One chain issue only — check `gh issue list --label orchestrator --state open` first and edit rather than open a second. Two chain issues means two truths.

## A4. Hand it over

Answer how many waves there are, then print one line per wave, copy-pasteable:

```
GH Issue #<chain#>, Wave 1
GH Issue #<chain#>, Wave 2
```

All of them start at once. Say which tickets are blocked at launch and which are `hitl`. Do not implement anything.

---

# §B Run wave K

## B1. Three reads, before any work

Read the chain issue, then compute — do not assume — three lists.

**Your frontier.** Runnable = open · unassigned · not `hitl` · no blocker whose state is open.

```bash
gh api repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by --jq '[.[] | select(.state=="open") | .number]'
```

Empty array means go. Two traps: `gh issue list --json blockedBy` returns an **object** — the edges are under `.nodes`, and `--jq` straight at the field is unreliable (`build-waves.md`) — and the list **includes already-closed blockers**, so filter on state every time. REST says `open`/`closed` lowercase; the JSON field says `OPEN`/`CLOSED`.

**Who waits on you.** Which of your tickets block someone else's. This is the read people skip, and it is what makes the mesh work for N sessions instead of two: you cannot announce a release you never knew you owed.

**Your flow-breaking `hitl`.** A `hitl` ticket matters *now* only if something's `blockedBy` points at it. One nobody waits on is the owner's to do whenever — never interrupt him for it. See B5.

## B2. Register, claim, isolate

Comment on the chain issue: your wave number and your session name from `ListAgents`, so other orchestrators can address you. Without this you can compute that you owe an announcement but not where to send it.

Then per ticket `gh issue edit <n> --add-assignee @me --add-label in-progress`, and `EnterWorktree` before the first edit.

## B3. Run the free tickets

**REQUIRED SUB-SKILL:** `superpowers:subagent-driven-development` — one subagent per ticket. Give it the ticket body verbatim; assume it has seen nothing of this conversation.
**REQUIRED SUB-SKILL:** `superpowers:verification-before-completion` before any completion claim.

Deferred tickets stay untouched and unassigned. Do not "just start" a blocked one.

## B4. Announce, every time

The moment a ticket that blocks someone closes, `SendMessage` that wave's orchestrator: the ticket number, that it is closed, and the PR. **Announce failures too** — a ticket that could not land leaves its waiter parked forever unless you say so.

On the receiving side: re-check `blocked_by` on GitHub before starting. The message is the fast path; the edge is the truth, and a mistaken "I'm done" must not start work. Wait for **all** your blockers to clear, not the first message that arrives.

## B5. Surface a flow-breaking `hitl` at claim time

At claim time — not when you walk up to the ticket hours later. Raised at the start, his answer lands while agents are still busy and the wait costs nothing; raised on arrival, the parallel window is already spent.

Comment the item on the chain issue. Then **one** session owns the decision sheet: the orchestrator of the **lowest-numbered wave still running**. It builds one dark HTML sheet at `~/Desktop/kouroshtrades-decisions.html` — every pending question, picks, free text, file drops, "Copy as markdown" — and reads answers back from `inbox/kouroshtrades-decisions.md`. Every other orchestrator contributes through the chain issue and never writes that file. He answers in one sitting; N sheets or N chat pings defeat the whole point.

## B6. Report parked, do not go quiet

When only blocked tickets remain, tell the user — which tickets, which wave, and **which kind of wait**: agent-gated ("Wave 1 is finishing #24, landing soon") or human-gated ("needs Kourosh, no ETA"). On a human-gated wait, stop holding and report. A silent session is indistinguishable from a dead one.

## B7. Close out on GitHub — this is the job, not the epilogue

1. Commit, push, open the PR. Never push to `master`, never force-push.
2. Per ticket: comment with what changed, the PR link, and **evidence per Done-when line**; `--remove-label in-progress`; close it *only* if Done-when actually passed. One that did not land stays open with a comment saying why.
3. Comment on the chain issue: what landed, what did not, the PR, any serialized file you touched.
4. Re-run your frontier — and send the §B4 announcements.

## Project conventions

These are this project's; replace them with your own repo's when adapting the skill. Ticket bodies carry `## Done when` (the acceptance contract), often `## Options` with an orchestrator recommendation, `## Evidence`, and `## Build slot`. Labels: `wayfinder:task` on work, `wayfinder:map` on the map, `wave:N`, `hitl`, `in-progress`, `orchestrator`, `needs-info`.

From `build-waves.md`, the rules that bite: serialized files (`proxy.ts`, `app/layout.tsx`, `vercel.json`, `AGENTS.md`, `DESIGN.md`, `app/sitemap.ts`, `lib/account/data.ts`) are handed **up** to the orchestrator, never edited by a worker; migration timestamps are assigned at dispatch, not discovered at merge; any ticket that moves money gets an Opus-level review pass; a dead worker is resumed with `SendMessage`, never re-dispatched; Persian is never invented — propose it on the issue and ship approved strings verbatim, no hamza; gates are `npm run typecheck && npm run lint && npm test && npm run build`.

## Red flags — stop

- "My wave is blocked" → waves do not block. One ticket does. Run the other fifteen.
- "I'll check the chain issue's status column" → there is none, by design. Query the edges.
- "The blocker's agent said it's done" → verify the edge before starting.
- "I'll tell him about the hitl ticket when I reach it" → too late. Claim time.
- "I'll write my own decisions sheet" → one sheet, one owner, lowest live wave.
- "I'll pick up a ticket from another wave" → you own one wave. Announce and hand over.
- "I'll close the tickets after the PR merges" → close them now. Nobody else will.
