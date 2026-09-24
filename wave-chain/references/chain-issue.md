Template for the chain issue body. Replace every `<…>`.

**This issue is an index and a registry. It is not a lock** — do not add a status column. The lock is the `blockedBy` edges on the tickets, which an agent queries. A hand-maintained column goes stale and idles agents over tickets that are free to run.

---

**Index and hand-off for the wave agents. This issue is not a lock.**

The lock is on the tickets themselves, as GitHub `blockedBy` edges you can query. `docs/agents/build-waves.md` is the authority: *"waves are a planning view, not a barrier."* With a lead (`/wave-chain --implement`), the lead launches waves three at a time, lowest first, into its WezTerm window; by hand, start as many as the machine allows.

Hand-off line for a session run by hand: `GH Issue #<this issue>, Wave <K>`

Chain label: `chain:<this issue>` - on this issue and on every ticket in it. Wave numbers are this chain's own; a `wave:K` ticket without this label belongs to another chain. <If other chains are open: "Also open: #<n> (<what>). Their waves are not ours; one lead per repo at a time.">

| Wave | What it is | Tickets | Blocked at launch |
|---|---|---|---|
| 1 | <one line> | <n> | — |
| 2 | <one line> | <n> | #<a> waits on #<b> |

## Your frontier — compute it, do not assume it

Your tickets = `chain:<this issue>` · `wave:<K>`. Runnable = open · unassigned · not `hitl` · no blocker whose state is open.

```bash
gh api repos/<owner>/<repo>/issues/<n>/dependencies/blocked_by \
  --jq '[.[] | select(.state=="open") | .number]'
```

Empty array means go. `gh issue list --json blockedBy` returns an object — edges are under `.nodes`, and the list includes already-closed blockers, so filter on state. Re-run after every close; closing one ticket often frees one in another wave.

## Declared edges

| Blocked | Waits on | Crosses waves | Why |
|---|---|---|---|
| #<a> | #<b> | <yes/no> | <one line> |

An agent finding one of these blocked leaves **that ticket** and runs its others. It does not idle.

## Orchestrator registry — comment yours on claim

| Wave | Session name | Claimed |
|---|---|---|
| <K> | <name from ListAgents> | <timestamp> |

This is how another orchestrator addresses you with `SendMessage` when it closes your blocker.

With a lead, the lead's own `lead: <session>, branch: …, chain PR: …, dev server: …, launched: …` comment sits here too, and every later launch, merge, kill, and `lead-handover` is one more line. Waves report to the session in the **latest** `lead:` comment. This thread is the lead's memory; it is rebuilt from here after a compaction or a handover.

## Waiting on the owner — flow-breaking only

A `hitl` ticket goes here **only if something's `blockedBy` points at it**. Post it the moment you find it, at claim time.

With a lead, the lead owns the decision sheet for the whole run. Otherwise the orchestrator of the **lowest-numbered wave still running** owns it: it assembles every item below into one dark HTML sheet at `~/Desktop/<repo>-decisions.html` and reads answers back from `inbox/<repo>-decisions.md`. No other session writes that file.

- [ ] #<n> — blocks #<m> (Wave <K>) — <the question, concretely>

## Wave <K> — <name> (<count>)
- [ ] #<n> <title>
      ↳ <trap, dependency, or "Moves money — Opus review pass at merge">

## Not in any wave
`hitl`, nobody waiting — the owner's, on his own schedule:
- #<n> <title>

## Rules every wave agent follows

`docs/agents/build-waves.md` is the authority. The ones that bite:

1. **Claim first:** `gh issue edit <n> --add-assignee @me --add-label in-progress`.
2. **Announce every close that frees someone** — and every failure that does not. `SendMessage` the waiting orchestrator, then verify the edge before acting on one.
3. **Serialized files** are handed to the orchestrator, never edited by a worker: <list>.
4. **Migration timestamps assigned at dispatch**, not discovered at merge.
5. **Money tickets get an Opus-level review pass** at merge.
6. **A dead worker is resumed, not re-dispatched.**
7. **Never invent Persian.** Propose on the issue, ship approved strings verbatim, no hamza.
8. **Gates:** `npm run typecheck && npm run lint && npm test && npm run build`. Never push to `master`.

## Finishing

1. Commit, push, open the PR titled `wave K: …`, against `wave-chain/<this issue>` when there is a lead, else `main`.
2. Per ticket: comment with evidence per Done-when line and the PR link, `--remove-label in-progress`, close — only if Done-when passed. One that did not land stays open with a comment saying why.
3. Comment here: what landed, what did not, serialized files touched.
4. Re-run your frontier and send your announcements.
5. `scripts/gh-audit.sh <this issue> <K>` must print `AUDIT PASS` before your `landed` line.

Leaving tickets open while reporting a wave finished is the failure this issue exists to prevent.
