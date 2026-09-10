# wave-chain

A Claude Code skill for running **many orchestrator sessions at once** over one GitHub backlog — one wave each, unblocking each other by message instead of by waiting.

You open N terminals and tell each one the same thing with a different number:

```
GH Issue #148, Wave 1
GH Issue #148, Wave 2
GH Issue #148, Wave 3
```

They all start immediately. They coordinate themselves.

---

## Why

The obvious way to parallelise a backlog is to cut it into waves and run them in order: wave 1, then wave 2, then wave 3. It wastes most of the parallelism you were trying to buy.

A wave is a planning view — a rough answer to *"what depends on roughly what"*. The real dependencies are between individual tickets, and there are only ever a handful of them. If wave 3 has sixteen tickets and exactly two of them wait on wave 2, freezing the whole wave idles an agent for hours over two tickets that fourteen others don't care about.

The second failure is subtler. If you track "which wave is released" in a table someone maintains by hand, that table is stale the moment a ticket closes, and every agent reading it is making decisions on fiction.

This skill inverts both:

- **The lock is per ticket, and it's queryable.** GitHub has native `blockedBy` dependency edges. An agent asks GitHub whether it's blocked; it never reads a status column and never guesses.
- **Release is a push, not a poll.** The session that closes a blocker *messages* the session that was waiting. No polling loops, no "are you done yet".

---

## How it runs

```
  chain issue #148  ─────────── index · declared edges · registry · owner questions
        │
        ├── Wave 1 agent ──┬─ #117 #114 #83 #144        all free → runs all four
        │                  └─ closes #115 ──┐
        │                                   │  SendMessage: "#115 is closed, PR #201"
        ├── Wave 2 agent ──┬─ #70 #116 …    │           14 tickets, runs 13
        │                  └─ #76 waits ────┘           starts when #70 lands
        │
        └── Wave 3 agent ──┬─ #79 #84 #113 …            16 tickets, runs 14
                           └─ #51 waits on #115 ◄───────┘  verifies the edge, then runs
```

Every orchestrator does three reads before it touches anything:

| Read | Why |
|---|---|
| Which of my tickets are **blocked** | so I defer those two and run the other fourteen |
| Which of my tickets **block someone else** | so I know I owe an announcement when they land |
| Which of my tickets need **the human** *and* have someone waiting | so I surface it now, not in four hours |

That middle read is the one that makes this work for N sessions rather than two. You cannot announce a release you never knew you owed.

---

## The parts people get wrong

**A blocked ticket parks the ticket, never the session.** An agent whose row says "blocked" runs everything else it owns first, and only truly waits when it has nothing free left.

**The message is the fast path; the edge is the truth.** When "I finished #115" arrives, the waiting agent re-queries GitHub before starting. A mistaken or optimistic claim shouldn't start work on a false release.

**Failures get announced too.** A ticket that *couldn't* land leaves its waiter parked forever unless someone says so.

**Wait for all your blockers, not the first message.** If #27 waits on both #24 and #25, one arrival isn't a green light.

**Human-gated waits are surfaced at claim time.** A ticket that needs a decision from you only matters *urgently* if something's `blockedBy` points at it — one nobody is waiting on is yours to do whenever, and should never interrupt. But a blocking one raised at the start means your answer lands while agents are still busy; raised on arrival, the parallel window is already spent. All of them collect on the chain issue, and exactly one session — the lowest-numbered wave still running — assembles them into a single decision sheet, so N agents never become N separate interruptions.

**A parked session reports itself.** It says which tickets, which wave, and whether the wait is agent-gated ("landing soon") or human-gated ("no ETA"). A silent session is indistinguishable from a dead one.

---

## The chain issue

One GitHub issue, labelled `orchestrator`, that every session reads. It is deliberately **not** a lock — there's no status column to go stale. It holds the wave index, the declared dependency edges with the reason for each, the registry where each orchestrator posts its session name on claim (that's how the others address it), the owner questions that are blocking someone, and the close-out rules.

[`references/chain-issue.md`](./references/chain-issue.md) is the template.

---

## Usage

| You type | It does |
|---|---|
| `/wave-chain` | Reads the open issues, converts prose dependencies into real `blockedBy` edges, writes the chain issue, tells you how many waves and prints the hand-off lines |
| `/wave-chain 2`, or `GH Issue #148, Wave 2` | Runs wave 2: computes its frontier, registers, claims, fans out subagents, announces, closes out on GitHub |

---

## Two `gh` traps worth knowing

Both cost real time to find:

```bash
# blockedBy comes back as an OBJECT, and includes already-CLOSED blockers.
# Filter on state or you'll treat finished work as a live block.
gh api repos/OWNER/REPO/issues/51/dependencies/blocked_by \
  --jq '[.[] | select(.state=="open") | .number]'
```

Creating an edge takes the blocker's **internal REST `id`**, not its issue number — pass the number and the edge silently points at the wrong ticket:

```bash
BLOCKER_ID=$(gh api repos/OWNER/REPO/issues/115 --jq .id)
gh api -X POST repos/OWNER/REPO/issues/51/dependencies/blocked_by -F issue_id=$BLOCKER_ID
```

REST reports `open`/`closed` lowercase; the GraphQL-backed `--json blockedBy` field reports `OPEN`/`CLOSED`.

---

## Adapting it

The protocol is generic. The `## Project conventions` section of `SKILL.md` is not — it names one repo's serialized files, its test gates, its labels and its copy rules. Replace that section with your own before using it elsewhere.

---

## Requires

The [`superpowers`](https://github.com/obra/superpowers) plugin — `subagent-driven-development` fans the wave out, `verification-before-completion` gates the completion claims.

Sessions address each other with `SendMessage` / `ListAgents`, so orchestrators must be able to see each other as peers.
