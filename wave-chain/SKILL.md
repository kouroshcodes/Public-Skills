---
name: wave-chain
description: 'Use when GitHub issues must be handed to several orchestrator sessions at once, one wave each, running in parallel and unblocking each other by message. Triggers on "GH Issue #N, Wave K", on asking how many waves there are, on auditing whether open issues are still real work, on a ticket that must wait for another session''s ticket to land, on a hitl ticket that is stalling someone else''s work, and on a new issue opened after the chain was already built. [kourosh]'
argument-hint: "--read (default) | --modify | --implement K | --human | --add <issue#>"
metadata:
  author: kourosh
---

N orchestrators start at the **same time**, one per wave, all pointed at one chain issue. Waves decide who owns which tickets. They are not barriers, and no wave waits for another wave as a unit.

**The lock is per ticket, and it is queryable.** GitHub's native `blockedBy` edges are the only lock. Never a status column, never prose in a body, never a guess. An orchestrator that finds one of its tickets blocked leaves that ticket and runs its others - it does not idle a whole wave over one edge.

**Release is a push.** The orchestrator that closes a blocker messages whoever was waiting. Nobody polls.

If the project has a build/orchestration protocol doc (here, `docs/agents/build-waves.md`), it is the authority on how a single wave is run. This skill is the protocol *between* orchestrators. Where they disagree, that doc wins.

## Modes

| Argument | Mode |
|---|---|
| none, or `--read` | **§R** - audit and report. Writes nothing. |
| `--modify` | **§M** - apply the plan to GitHub. Issues only, no code. |
| `--implement K`, or "GH Issue #N, Wave K" | **§I** - run wave K |
| `--human` | **§H** - own the decisions sheet, clear the `hitl` blockers |
| `--add <issue#>` | **§D** - graft a new issue into a chain that is already running |

## Two invariants, every mode

**`--read` writes nothing.** Not an issue, not a label, not a comment, not an edge, not a close. A stale ticket that obviously shipped is still only a *recommendation* in `--read`. The default has to be safe to run by accident, or it stops being the default.

**Code is the only evidence.** Never a doc, never a state tracker, never a handoff file, never memory, never what a previous session reported. `BUILD_STATE.md` says a feature shipped and the repo says otherwise: the repo is right. Every verdict carries `file:line`, or it is not a verdict.

---

# §R Read (default)

## R1. Read the real issues

```bash
gh issue list --state open --limit 300 --json number,title,labels,url,body
```

Never restate a ticket from memory. If `wave:*` labels exist they **are** the plan - group by them, do not re-cut. Only unlabelled tickets need placing.

## R2. Verify every ticket against the codebase

An issue tracker drifts. Tickets get fixed by an unrelated PR, get superseded, or were written against a design that no longer exists. Feeding those to an orchestrator spends a whole session's parallelism on work that is already in `main`.

So every open ticket is read against the actual code and gets one of three verdicts:

| Verdict | Meaning | Required evidence |
|---|---|---|
| `SHIPPED` | Every `## Done when` line is already true in the repo | `file:line` per Done-when line |
| `PARTIAL` | Some Done-when lines pass, some do not | what passes, with `file:line`, and what is left |
| `OPEN` | Real work, or you cannot settle it either way from the code | the grep that found nothing |

**Undeterminable is `OPEN`.** A ticket you cannot prove shipped is never `SHIPPED`. Re-running a done ticket costs an hour; dropping a live one leaves a hole nobody is looking for.

Fan out to verify: one subagent per batch of tickets, given the ticket bodies verbatim. **Cap the fan-out at 3 concurrent subagents** and give none of them `tsc` - the dev machine has 8GB and a wider fan-out has crashed it.

Say it in the subagent's prompt: read the code, not the docs. One that comes back citing `BUILD_STATE.md`, a handoff file, or an archive as proof gets sent back for `file:line`.

## R3. Dependencies and waves

A dependency that lives only in prose ("after the endpoint lands") cannot be queried, so an agent guesses. List each prose dependency you find as a **proposed edge**, and list the edges that already exist:

```bash
gh api repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by --jq '[.[] | select(.state=="open") | .number]'
```

Then cut the `OPEN` and `PARTIAL` tickets into waves, respecting those edges: a ticket never sits in an earlier wave than its blocker.

## R4. Carve out what is not agent work

`hitl` (the owner's, never claimed by an agent), dated tickets, and the `wayfinder:map` ticket. List them separately. Flag any `hitl` that something's `blocked_by` points at: that one is on the critical path, and §H exists for it.

## R5. Report

Print, in this order: the `SHIPPED` list with its evidence and a "recommend close" note, the `PARTIAL` list with what remains, the proposed wave cut, the proposed edges, the edges that already exist, the `hitl` carve-out, and the number of waves.

Close with the line that says what happens next: `/wave-chain --modify` writes this to GitHub.

---

# §M Modify

Issues only. No code, no branches, no PRs.

## M1. Run §R first

Never write from memory of an earlier read in the same session. Re-read. Tickets move.

## M2. Show the proposal, then stop

Print the §R5 report, plus exactly what you are about to write: which issues close, which labels land, which edges get created, what the chain issue will say.

**Wait for the owner's go.** Not a single label before it. A wave cut across 50 tickets is a judgement call, and labels plus edges on 50 issues are slow and annoying to undo. He answers in one word, in chat - there is no sheet and no inbox file for this one. Nothing else counts as the go, and silence is not it. That word costs nothing next to a wrong cut written 50 times.

## M3. Close what shipped

Per `SHIPPED` ticket: comment the evidence (`file:line` per Done-when line), then close. The evidence goes on the issue, not only in your report - the next person to open that ticket needs to see why it died.

`PARTIAL` never closes. It gets a comment saying what already passed, and it enters the chain with the rest.

## M4. Label the waves

`gh issue edit <n> --add-label wave:K` across the survivors.

## M5. Make every dependency a real edge

```bash
BLOCKER_ID=$(gh api repos/{owner}/{repo}/issues/<blocker> --jq .id)
gh api -X POST repos/{owner}/{repo}/issues/<blocked>/dependencies/blocked_by -F issue_id=$BLOCKER_ID
```

The endpoint takes the blocker's **internal REST `id`**, not its issue number - passing the number silently points the edge at the wrong ticket. Verify every edge afterwards with the read query in R3.

## M6. Write the chain issue

Fill [`references/chain-issue.md`](references/chain-issue.md), then:

```bash
gh issue create --title "Wave chain - <YYYY-MM-DD>" --label orchestrator --body-file <path>
```

One chain issue only - check `gh issue list --label orchestrator --state open` first and edit rather than open a second. Two chain issues means two truths.

## M7. Hand it over

Answer how many waves there are, then print one line per wave, copy-pasteable:

```
GH Issue #<chain#>, Wave 1
GH Issue #<chain#>, Wave 2
```

All of them start at once. Say which tickets are blocked at launch and which are `hitl`. Do not implement anything.

---

# §I Implement wave K

## I1. Three reads, before any work

Read the chain issue, then compute - do not assume - three lists.

**Your frontier.** Runnable = open · unassigned · not `hitl` · no blocker whose state is open. Use the R3 query; an empty array means go.

Two traps: `gh issue list --json blockedBy` returns an **object** - the edges are under `.nodes`, and `--jq` straight at the field is unreliable (`build-waves.md`) - and the list **includes already-closed blockers**, so filter on state every time. REST says `open`/`closed` lowercase; the JSON field says `OPEN`/`CLOSED`.

**Who waits on you.** Which of your tickets block someone else's. This is the read people skip, and it is what makes the mesh work for N sessions instead of two: you cannot announce a release you never knew you owed.

**Your flow-breaking `hitl`.** A `hitl` ticket matters *now* only if something's `blockedBy` points at it. One nobody waits on is the owner's to do whenever - never interrupt him for it. See §H.

## I2. Register, claim, isolate

Comment on the chain issue: your wave number and your session name from `ListAgents`, so other orchestrators can address you. Without this you can compute that you owe an announcement but not where to send it.

Then claim **your frontier tickets only** - the ones I1 computed as runnable: `gh issue edit <n> --add-assignee @me --add-label in-progress`. A blocked ticket stays unassigned and unlabelled, so whoever clears it can see at a glance that nobody is on it. `EnterWorktree` before the first edit.

## I3. Run the free tickets

**REQUIRED SUB-SKILL:** `superpowers:subagent-driven-development` - one subagent per ticket. Give it the ticket body verbatim; assume it has seen nothing of this conversation.
**REQUIRED SUB-SKILL:** `superpowers:verification-before-completion` before any completion claim.

Deferred tickets stay untouched and unassigned. Do not "just start" a blocked one.

## I4. Announce, every time

The moment a ticket that blocks someone closes, `SendMessage` that wave's orchestrator: the ticket number, that it is closed, and the PR. **Announce failures too** - a ticket that could not land leaves its waiter parked forever unless you say so.

On the receiving side: re-check `blocked_by` on GitHub before starting. The message is the fast path; the edge is the truth, and a mistaken "I'm done" must not start work. Wait for **all** your blockers to clear, not the first message that arrives.

## I5. Surface a flow-breaking `hitl` at claim time

At claim time - not when you walk up to the ticket hours later. Raised at the start, his answer lands while agents are still busy and the wait costs nothing; raised on arrival, the parallel window is already spent.

Comment the item on the chain issue, then let §H carry it.

## I6. Report parked, do not go quiet

When only blocked tickets remain, tell the user - which tickets, which wave, and **which kind of wait**: agent-gated ("Wave 1 is finishing #24, landing soon") or human-gated ("needs Kourosh, no ETA"). On a human-gated wait, stop holding and report. A silent session is indistinguishable from a dead one.

## I7. Close out on GitHub - this is the job, not the epilogue

1. Commit, push, open the PR. Never push to `master`, never force-push.
2. Per ticket: comment with what changed, the PR link, and **evidence per Done-when line**; `--remove-label in-progress`; close it *only* if Done-when actually passed. One that did not land stays open with a comment saying why.
3. Comment on the chain issue: what landed, what did not, the PR, any serialized file you touched.
4. Re-run your frontier - and send the §I4 announcements.

---

# §H Human

One session owns the decision sheet: the orchestrator of the **lowest-numbered wave still running**. Every other orchestrator contributes through the chain issue and never writes that file. N sheets or N chat pings defeat the whole point.

Ownership does not transfer by itself. Before you finish your wave, hand the sheet over: `SendMessage` the next lowest wave still running, and say on the chain issue who owns it now. An orchestrator that exits quietly leaves the sheet ownerless and every pending question unasked.

1. Collect every pending `hitl` item from the chain issue, plus your own. Mark the ones something is `blocked_by`; those are the only urgent ones.
2. Build one dark HTML sheet at `~/Desktop/kouroshtrades-decisions.html`: every pending question, picks, free text, file drops, "Copy as markdown". Critical-path items first.
3. Read answers back from `inbox/kouroshtrades-decisions.md`. Do not chase him in chat; he answers the sheet in one sitting.
4. Apply each answer: comment it on its ticket, and where an answer clears a blocker, close that blocker and send the §I4 announcement to whoever was waiting.

---

# §D Add an issue to a running chain

A new issue, opened after the chain was built. `--modify` cannot take it: `--modify` assumes nobody is running yet, and would rewrite a plan that sessions are already executing.

1. **Verify it first.** §R2 on this one ticket. A brand new issue can already be shipped, and grafting dead work into a live chain is worse than leaving it out.
2. **Find its edges, both directions.** What open tickets it needs, and which open tickets now need it. Create them for real with the M5 call, `id` not number.
3. **Place it.** Never earlier than the wave of its deepest open blocker. If nothing blocks it, it joins the lowest wave still running. Label `wave:K`.
4. **Append to the chain issue.** A comment saying which ticket, which wave, which edges, and why it landed there.
5. **Message that wave's orchestrator.** `SendMessage`, with the ticket number and its blockers. **This is the step that matters.** That session computed its frontier before your ticket existed and will never recompute on its own - a label alone is invisible to it. If that wave has already finished, say so and hand the ticket to the lowest wave still running instead.

## Project conventions

These are this project's; replace them with your own repo's when adapting the skill. Ticket bodies carry `## Done when` (the acceptance contract), often `## Options` with an orchestrator recommendation, `## Evidence`, and `## Build slot`. Labels: `wayfinder:task` on work, `wayfinder:map` on the map, `wave:N`, `hitl`, `in-progress`, `orchestrator`, `needs-info`.

From `build-waves.md`, the rules that bite: serialized files (`proxy.ts`, `app/layout.tsx`, `vercel.json`, `AGENTS.md`, `DESIGN.md`, `app/sitemap.ts`, `lib/account/data.ts`) are handed **up** to the orchestrator, never edited by a worker; migration timestamps are assigned at dispatch, not discovered at merge; any ticket that moves money gets an Opus-level review pass; a dead worker is resumed with `SendMessage`, never re-dispatched; Persian is never invented - propose it on the issue and ship approved strings verbatim, no hamza; gates are `npm run typecheck && npm run lint && npm test && npm run build`.

## Red flags - stop

- "My wave is blocked" → waves do not block. One ticket does. Run the other fifteen.
- "I'll check the chain issue's status column" → there is none, by design. Query the edges.
- "The blocker's agent said it's done" → verify the edge before starting.
- "The docs say this one shipped" → docs are not evidence. `file:line` or it stays open.
- "This one is obviously dead, I'll close it while reading" → `--read` writes nothing. Recommend it; `--modify` closes it.
- "I'll write the labels, he'll say if the cut is wrong" → the cut is confirmed before the first write, not after the fiftieth.
- "I'll tell him about the hitl ticket when I reach it" → too late. Claim time.
- "I'll write my own decisions sheet" → one sheet, one owner, lowest live wave.
- "I labelled the new ticket, they'll pick it up" → they will not. The frontier was already computed. Message them.
- "I'll pick up a ticket from another wave" → you own one wave. Announce and hand over.
- "I'll close the tickets after the PR merges" → close them now. Nobody else will.
