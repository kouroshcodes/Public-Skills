---
name: wave-chain
description: 'Use when GitHub issues must be handed to several orchestrator sessions at once, one wave each, running in parallel and unblocking each other by message. Triggers on "GH Issue #N, Wave K", on asking how many waves there are, on auditing whether open issues are still real work, on a ticket that must wait for another session''s ticket to land, on a hitl ticket that is stalling someone else''s work, and on a new issue opened after the chain was already built. [kourosh]'
argument-hint: "--read (default) | --modify | --implement (lead) | --implement K | --human | --add <issue#>"
metadata:
  author: kourosh
---

N orchestrators, one per wave, all pointed at one chain issue, as many running at once as the machine allows. Waves decide who owns which tickets. They are not barriers, and no wave waits for another wave as a unit.

**The lock is per ticket, and it is queryable.** GitHub's native `blockedBy` edges are the only lock. Never a status column, never prose in a body, never a guess. An orchestrator that finds one of its tickets blocked leaves that ticket and runs its others - it does not idle a whole wave over one edge.

**Release is a push.** The orchestrator that closes a blocker messages whoever was waiting. Nobody polls.

If the project has a build/orchestration protocol doc (here, `docs/agents/build-waves.md`), it is the authority on how a single wave is run. This skill is the protocol *between* orchestrators. Where they disagree, that doc wins.

## Modes

| Argument | Mode |
|---|---|
| none, or `--read` | **§R** - audit and report. Writes nothing. |
| `--modify` | **§M** - apply the plan to GitHub. Issues only, no code. |
| `--implement` with no number | **§L** - lead: launch every wave in its own WezTerm tab, merge their PRs into one chain branch, and be the only session that talks to the owner |
| `--implement K`, or "GH Issue #N, Wave K" | **§I** - run wave K |
| `--human` | **§H** - own the decisions sheet, clear the `hitl` blockers |
| `--add <issue#>` | **§D** - graft a new issue into a chain that is already running |

## Two invariants, every mode

**`--read` writes nothing.** Not an issue, not a label, not a comment, not an edge, not a close. A stale ticket that obviously shipped is still only a *recommendation* in `--read`. The default has to be safe to run by accident, or it stops being the default.

**Nothing starts without the word.** `--modify` waits for the owner's go before the first label; the lead (§L0) waits for `confirm` before the first tab. Both print what they are about to do in plain words first. A run the owner did not confirm is a run he did not want.

**GitHub is the deliverable.** The owner comes back and opens GitHub, not the chat. A ticket closed with its evidence comment, a PR whose body says what it contains, a chain PR ready for review - that is the work. A chat summary is a copy of what is already on GitHub, never a substitute for it, and "see the PR for details" is only ever written after the details are in the PR. Whether GitHub is right is not a judgement: `scripts/gh-audit.sh` checks the state of every wave ticket and PR, and nothing is `landed` while it prints a `FAIL` line. Its output is the close-out; the agent's memory of having closed things is not.

**Code is the only evidence.** Never a doc, never a state tracker, never a handoff file, never memory, never what a previous session reported. `BUILD_STATE.md` says a feature shipped and the repo says otherwise: the repo is right. Every verdict carries `file:line`, or it is not a verdict.

## Shared machine

Every wave runs on one laptop. These are hard caps on what runs **at the same time**, not on how many waves a project has - a six-wave chain runs through them three at a time.

**Five parallel agents per wave, maximum.** Count every subagent you have in flight, not the tickets you own. Three waves running at once means fifteen agents on one machine, which is already the ceiling; the lead never has more than three wave sessions live (§L1). A sixth agent in a wave does not finish sooner, it slows the other five and pushes the machine into swap. More tickets than slots: queue them and dispatch as agents return.

**One dev server, shared by every session.** Never start a second. With a lead (§L), the lead starts it before any wave exists and is the only session that stops it; a wave never starts one and never kills one, whatever port 3000 says. Without a lead, before you start anything:

```bash
lsof -ti:3000
```

A PID means the shared server is already up - use it, and it makes no difference which wave started it. Start one only when nothing answers. While any other session is live, never kill it, whoever started it: another wave is probably mid-verification on it. A second `next dev` on port 3001 is not a workaround, it is the same RAM and a second set of file watchers on the same tree.

**Last session out reaps it - without a lead only.** With a lead, §L6 reaps and you never touch it. Otherwise, closing out your wave, check `ListAgents`. No other orchestrator still running means you are the last one, so kill the shared server before you finish, whoever started it:

```bash
lsof -ti:3000 | xargs kill
```

Any peer still live and you leave it up. This is the only deliberate kill, and it is what keeps the shared server from outliving the whole chain: nobody else's close-out will reap it, and a server left up for hours is the one that silently misses a route file added after it booted.

**Context windows are capped below the model's.** A session that runs to 967K tokens before compaction has spent most of that on a lossy tail; the smart part of a session is its first few hundred thousand tokens. So: wave tabs run with `--autocompact 600k` (the launcher sets it), the lead with `--autocompact 450k` (the owner starts it that way, see M7; a successor lead is launched that way by §L7). A wave that compacts finishes its wave on the summary plus GitHub; a lead that compacts hands over (§L7).

These numbers are this machine's, like `## Project conventions` below. Change them together with that section when you adapt the skill.

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

Fan out to verify: one `haiku` subagent per batch of tickets, given the ticket bodies verbatim - grep and cite needs no reasoning depth. **Cap this fan-out at 3 concurrent subagents** - stricter than the five in Shared machine, because verifiers all grep the whole tree at once - and give none of them `tsc`, which has crashed this 8GB machine before.

Say it in the subagent's prompt: read the code, not the docs. One that comes back citing `BUILD_STATE.md`, a handoff file, or an archive as proof gets sent back for `file:line`.

## R3. Dependencies and waves

A dependency that lives only in prose ("after the endpoint lands") cannot be queried, so an agent guesses. List each prose dependency you find as a **proposed edge**, and list the edges that already exist:

```bash
gh api repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by --jq '[.[] | select(.state=="open") | .number]'
```

Then cut the `OPEN` and `PARTIAL` tickets into waves. The cut is mechanical, and the report shows its working so the owner checks the edges, not the arithmetic:

1. **Clean first.** A ticket without `## Done when` cannot be verified, so it cannot be scheduled: label it `needs-info` and leave it out. A ticket that is three tickets is split before it is placed.
2. **Real edges only.** B depends on A when B's Done-when cannot be built or tested without A's code: a migration B reads, an endpoint B calls, a type B imports, a component B renders inside. "Same area", "nicer first", and "related" are not edges. Every proposed edge carries its reason. A fake edge adds a wave, and depth is the only thing that costs time.
3. **Wave = longest path from a root.** No open blocker: wave 1. Otherwise: the wave after the deepest blocker. Never earlier, never later. Print the layers.
4. **Never balance by adding edges.** Uneven is fine. Waves run in parallel and only tickets wait, so a two-ticket wave 5 costs almost nothing.
5. **Split a wide layer by area, not by edge.** A layer over ~20 tickets becomes several waves with no edges between them, grouping tickets that touch the same files. Two sessions run it instead of one queueing, and tickets that would conflict at merge sit in the same wave where one orchestrator serializes them. Under ~5 tickets and the edges allow it: fold into the neighbour.
6. **Foundations first inside a wave.** Order by how many tickets depend on each one; the migration five tickets wait on gets the first `## Build slot`, not the fifth.
7. **`hitl`-blocked work goes in the last wave**, so the run does everything it can before it stops on the owner. The `hitl` ticket itself is outside the waves.
8. **Migrations in one wave, in order.** Timestamps are assigned at dispatch; spread across waves, two sessions assign colliding ones.

The number of waves is the depth of the graph plus the area splits. It is whatever the work is; three is how many run at once, not a budget.

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

Answer how many waves there are, then print the one way the owner should start it:

```
wave-chain
```

That is the `scripts/start-lead.sh` alias: it finds the open chain issue, names the session `wc<chain#>-lead`, sets the 450k window and Opus, and runs `--implement`. Without the alias, the long form is `claude --name wc<chain#>-lead --autocompact 450k` then `/wave-chain --implement`. For running a single wave by hand, one line per wave:

```
GH Issue #<chain#>, Wave 1
GH Issue #<chain#>, Wave 2
```

Say which tickets are blocked at launch and which are `hitl`. Do not implement anything.

---

# §I Implement wave K

## I1. Three reads, before any work

Read the chain issue, then compute - do not assume - three lists.

**Your frontier.** Runnable = open · unassigned · not `hitl` · no blocker whose state is open. Plus, if you were relaunched (§L4b): open · assigned to `@me` · `in-progress` · `wave:K` - that is your own unfinished work, resume it. Use the R3 query; an empty array means go.

Two traps: `gh issue list --json blockedBy` returns an **object** - the edges are under `.nodes`, and `--jq` straight at the field is unreliable (`build-waves.md`) - and the list **includes already-closed blockers**, so filter on state every time. REST says `open`/`closed` lowercase; the JSON field says `OPEN`/`CLOSED`.

**Who waits on you.** Which of your tickets block someone else's. This is the read people skip, and it is what makes the mesh work for N sessions instead of two: you cannot announce a release you never knew you owed.

**Your flow-breaking `hitl`.** A `hitl` ticket matters *now* only if something's `blockedBy` points at it. One nobody waits on is the owner's to do whenever - never interrupt him for it. See §H.

## I2. Register, claim, isolate

Comment on the chain issue: your wave number and your session name - `wc<chain#>-wave<K>` when the launcher started you, otherwise whatever `ListAgents` shows - so other orchestrators can address you. Without this you can compute that you owe an announcement but not where to send it.

Then claim **your frontier tickets only** - the ones I1 computed as runnable: `gh issue edit <n> --add-assignee @me --add-label in-progress`. A blocked ticket stays unassigned and unlabelled, so whoever clears it can see at a glance that nobody is on it. `EnterWorktree` before the first edit. When the chain issue carries a `lead:` comment, base your worktree on `origin/wave-chain/<chain#>` from that comment, not on `main`.

## I3. Run the free tickets

**REQUIRED SUB-SKILL:** `superpowers:subagent-driven-development` - one subagent per ticket, **five in flight at most** (Shared machine). More free tickets than slots: queue them and dispatch as agents return. Give each the ticket body verbatim; assume it has seen nothing of this conversation.

**Worker model, per ticket:** `sonnet` by default. `opus` for any ticket that moves money, touches a serialized file, or carries a `## Options` section the orchestrator had to decide - those are the ones where a cheaper worker's mistake costs more than the model. Never `haiku` for a worker.
**REQUIRED SUB-SKILL:** `superpowers:verification-before-completion` before any completion claim.

Deferred tickets stay untouched and unassigned. Do not "just start" a blocked one.

## I4. Announce, every time

The moment a ticket that blocks someone closes, `SendMessage` that wave's orchestrator: the ticket number, that it is closed, and the PR. With a lead, "closed" means the lead has merged your PR into the chain branch - announce after the lead's merge confirmation, not after opening the PR, or the waiter branches from a tree that lacks your code. **Announce failures too** - a ticket that could not land leaves its waiter parked forever unless you say so.

On the receiving side: re-check `blocked_by` on GitHub before starting. The message is the fast path; the edge is the truth, and a mistaken "I'm done" must not start work. Wait for **all** your blockers to clear, not the first message that arrives.

## I5. Surface a flow-breaking `hitl` at claim time

At claim time - not when you walk up to the ticket hours later. Raised at the start, his answer lands while agents are still busy and the wait costs nothing; raised on arrival, the parallel window is already spent.

Comment the item on the chain issue, then let §H carry it.

## I6. Report parked, do not go quiet

When only blocked tickets remain, report - which tickets, which wave, and **which kind of wait**: agent-gated ("Wave 1 is finishing #24, landing soon") or human-gated ("needs Kourosh, no ETA"). On a human-gated wait, stop holding and report. A silent session is indistinguishable from a dead one. With a lead, a human-gated wait also means you are finished: the owner is away and answers when he is back, so send the `parked-human` line, leave the ticket open and unassigned, do your I7 close-out for everything that did land, and exit. The lead lists it in the final summary as waiting on him; nobody idles in a tab for hours over it.

**Where the report goes depends on one observable fact.** If the chain issue carries a `lead:` registration comment (§L2), you were launched by a lead: `SendMessage` the report to the session named in the **latest** such comment - re-read it before every message, leads hand over (§L7) - and write nothing for the owner - he is not reading your tab. If there is no `lead:` comment, you were opened by hand and the owner is your reader: tell him in chat. The same routing applies to every I7 close-out summary and every §I5 `hitl` item.

**A message to the lead is exactly this, and nothing after it:**

```
wave <K>  #<ticket>  <ready | parked-agent | parked-human | failed | landed>  <PR link or ->
<one line: what, or who it waits on>
```

Anything longer - a log, a diff, a stack trace, a paragraph - goes as a comment on the ticket, and the message carries the ticket number. The lead has to hold every wave's messages for the whole run; the ticket only has to hold yours.

## I7. Close out on GitHub - this is the job, not the epilogue

1. Commit, push, open the PR titled `wave K: <what>` - the audit finds your PR by that prefix. With a lead, `gh pr create --base wave-chain/<chain#>` - never against `main` - then `SendMessage` the lead a `ready` line in the §I6 shape, and keep running your other tickets while you wait for its merge confirmation - only the announcement waits, not you. Without a lead, target `main` as before. Never push to `master`, never force-push.
2. Per ticket: comment with what changed, the PR link, and **evidence per Done-when line**; `--remove-label in-progress`; close it *only* if Done-when actually passed. One that did not land stays open with a comment saying why.
3. Comment on the chain issue: what landed, what did not, the PR, any serialized file you touched.
4. Re-run your frontier - and send the §I4 announcements.
5. **Audit before you say landed.** Run `~/.claude/skills/wave-chain/scripts/gh-audit.sh <chain#> <K>`. Every `FAIL` line names a ticket or PR whose GitHub state does not match a finished wave: fix it on GitHub and rerun until it prints `AUDIT PASS`. Only then send the `landed` line, and that line carries the words `audit: pass`. A `landed` line without them is a lie the lead will catch at L6, when it is expensive.

---

# §L Lead - `--implement` with no wave number

The owner opens one session - on Opus - and talks to one session. The lead is a manager, not a wave: it launches, relays, merges, and finishes last. It runs no tickets and reads no diffs. Its context has to survive a run of many hours, so every rule below is about keeping it small.

## L0. Brief the owner, then wait for the word

Nothing happens before this - no branch, no server, no tab. Read the chain issue and every open ticket it lists, and print a brief the owner can read in a minute, written for someone who has not opened a ticket in weeks:

```
Wave chain #148 - 23 tickets, 4 waves, 3 waiting on you

Wave 1 (7)
  #112  Show the account balance on the dashboard instead of only in settings
  #117  Let a user download last month's statement as a PDF
  ...
Wave 2 (9)   - starts once wave 1 tickets it needs have landed
  #131  Send an email when a deposit arrives
  ...
Waiting on you (3) - skipped this run, listed in the PR at the end
  #140  Which bank goes first? (needs your pick)

Then: one branch, one draft PR, one dev server, 3 tabs at a time, and I report here.
Say "confirm" to start, or tell me what to change.
```

The rules for those lines: one line per ticket, plain words, what the user of the app gets - never the mechanism. "Let a user download the statement" not "add a PDF export endpoint"; "fix the page that goes blank on refresh" not "hydration mismatch". No file names, no table names, no library names, no acronyms. If a ticket cannot be said in one plain sentence, that is a fact about the ticket worth reporting - say so under it in a second line. Do not re-verify tickets against the code here; that was `--modify`'s job and it is expensive - this is a reading, not an audit.

Then stop. The word is `confirm`, in chat. Anything else is a change request: apply it to the brief (never to GitHub - a wave move or a dropped ticket is `--modify`'s to write), print it again, and wait again. Silence is not the word.

## L1. Branch, count, launch

Three checks before anything, each a stop-and-report if it fails: there is exactly one open `orchestrator` issue with `wave:*` labels on tickets (otherwise the owner runs `--modify` first); `git status --porcelain` is empty in the repo root (the chain branch is cut from this checkout, and a dirty tree would carry the owner's uncommitted work onto it); `wezterm cli list` answers.

Cut the chain branch, from the default branch, and push it:

```bash
git fetch origin && git switch -c wave-chain/<chain#> origin/main && git push -u origin wave-chain/<chain#>
```

Start the shared dev server now, from your checkout of the chain branch, before a single wave exists - two tabs that both find port 3000 empty will both start one, and that race is only closed by starting it first:

```bash
lsof -ti:3000 || (npm run dev >/dev/null 2>&1 &) ; sleep 5; lsof -ti:3000
```

A PID means it is up. It serves the chain branch, so every merge in L4 is live on it without a restart. Put the PID in your L2 comment.

Then open the one PR the owner will ever read, as a draft, `wave-chain/<chain#>` into `main`, titled `Wave chain #<chain#>`. Its body is a checklist, one line per wave ticket, grouped by wave, unticked:

```
## Wave 1
- [ ] #12 <title>
- [ ] #15 <title>
## Wave 2
...
## Waiting on Kourosh
(filled at the end)
```

That body is the progress view: it is ticked as merges land (L4), so opening the PR at any time shows what is in it. It stays a draft until L6. Every wave's work lands on this branch and nowhere else; the owner previews and checks one PR, not N.

Read the chain issue and take the wave count from it - never from memory of a `--modify` in another session. Then launch waves as real sibling sessions, one WezTerm tab each, from the skill's launcher - **at most three live at once**, lowest-numbered first:

```bash
~/.claude/skills/wave-chain/scripts/launch-waves.sh <chain#> 1 3 <repo-dir>
```

The launcher prints one `wave K -> wezterm pane P` line per tab; keep those pane ids in your L2 comment. Each time a wave sends `landed` (or is declared dead twice, §L4b), close its tab - `wezterm cli kill-pane --pane-id P` - and launch the next unlaunched wave into the freed slot. Later waves are ordered after their blockers, so starting them late costs almost nothing, and starting six at once puts thirty agents on an eight-gigabyte machine. Wave 1 is a tab like the others. The lead running a wave itself is the single biggest way its context fills: five subagents' prompts, results, and verification output, all landing in the one session that has to last the longest.

Sibling sessions, not subagents: a wave needs its own worktree, its own five-agent budget, and a name in `ListAgents` that peers can message. Subagents have none of that, and they die with the parent.

The launcher only spawns tabs in the WezTerm window it runs in. It refuses when `wezterm cli` cannot reach a WezTerm session - report that to the owner and stop. Never fall back to Terminal.app, `open -a`, or `osascript`; a native terminal window is a different app, and it is exactly what the owner does not want. The launcher starts every child in `auto` permission mode, because a child that stops on a permission prompt in a tab nobody watches is a dead wave. `WAVE_CLAUDE_FLAGS` overrides that only when the owner has set it himself; never ask him to.

## L2. Register as lead

**Session names are a convention, not a discovery.** The launcher starts every session with `--name`: waves are `wc<chain#>-wave<K>`, the lead is `wc<chain#>-lead`, a successor lead is `wc<chain#>-lead-2`, `-3`, and so on. Any session can address any other from the chain number alone, and `ListAgents` reads as a roster instead of a list of conversation titles. A session that was started without `--name` (the owner ran a wave by hand) still posts whatever name `ListAgents` shows it; the registration comment is the fallback, the convention is the fast path.

Comment on the chain issue before the children register: `lead: <your ListAgents session name>, branch: wave-chain/<chain#>, chain PR: #<pr>, dev server: pid <pid> on :3000, launched: wave 1 pane P1, wave 2 pane P2, wave 3 pane P3, of <N>`. Every later launch, kill, and handover is another one-line comment in the same shape.. This comment is the switch every §I6 reads to decide whether its reports go to you or to the owner. Missing it, the children will write into their own tabs and the owner reads nothing.

## L3. The chain issue is your memory

Your context will be compacted during a long run. Plan for it: nothing you need later lives only in your head. Every event - a launch, a merge, a bounce, a relay to the owner, a `hitl` answer forwarded - is one line commented on the chain issue as it happens. After a compaction, or whenever you are unsure what state a wave is in, rebuild from the chain issue and the `blocked_by` edges, never from what you remember. Read it with `--jq` down to the fields you need; never pull whole issue bodies into context to find one line.

## L4. Merge through an agent, never by hand

A child's PR targets `wave-chain/<chain#>` and stays open until it is merged into the chain branch. You are the only merger, but you never merge in your own context. Per "PR ready" message, dispatch one `opus` merge subagent with this brief: in the repo root checkout (the one on `wave-chain/<chain#>`, not a worktree - the dev server serves this tree, so a merge here is live on it at once), merge PR #<n> into `wave-chain/<chain#>`, run the gates, resolve any conflict on the chain branch, push, **smoke it on the dev server** - for every Done-when line of the tickets in that PR that names a route, a page, or a visible behaviour, hit it on `http://localhost:3000` (curl for status and expected text; a browser check when a Done-when is visual) and read the server log for new errors - tick every ticket that PR closed in the chain PR body (`- [ ] #t` becomes `- [x] #t (PR #n)`, via `gh pr edit --body-file`), and return **only** this:

```
PR: #<n>   result: merged | conflict-resolved | bounced
gates: pass | fail <which>
smoke: pass | fail <route or behaviour> | n/a
conflicts: none | <files>
note: <one line>
```

The merge is the only moment in the run where a change is observable in the running app: a worker's tree is a worktree the shared server does not serve. So a `smoke: fail` bounces the PR exactly like a gate failure, with what was hit and what came back commented on the PR - a page that builds, lints, and passes its unit tests can still render blank, and this is the line that catches it. A `bounced` PR is reverted from the chain branch by the same agent before it returns, so the branch is never left carrying a change that failed.

Diffs, gate logs, and conflict hunks stay in the merge agent. A `bounced` verdict goes back to the child by `SendMessage` with the link to the failure comment the agent left on the PR, not with the log text. One merge agent at a time, so two waves' PRs never race on the branch.

Only after a blocking ticket's PR is merged does its §I4 announcement go out: confirm the merge to the child, and the child announces. A waiter then starts from `origin/wave-chain/<chain#>`, never from `main`.

## L4b. A wave that vanished

A wave session gone from `ListAgents` without a `landed` line is dead, not done (a wave that has landed is one *you* closed, so its absence is expected). Relaunch it once, that wave only:

```bash
~/.claude/skills/wave-chain/scripts/launch-waves.sh <chain#> <K> <K> <repo-dir>
```

Comment the relaunch on the chain issue. The relaunched session recomputes its frontier from GitHub; tickets labelled `in-progress` and assigned to `@me` under `wave:K` are its own unfinished work, and it resumes them rather than skipping them as claimed. A wave that dies twice is reported to the owner as such, and its tickets stay open.

## L5. Relay, both directions, one line each

Children report in the fixed shape of §I6. You forward each to the owner as it arrives, one line, merged with nothing and softened into nothing: a failure is reported as a failure. Do not batch until the end. The other direction too: an answer the owner gives you in chat that a child needs goes to that child by `SendMessage`, with the ticket number, and a one-line comment on the chain issue that it was forwarded.

You own the §H decisions sheet for the whole chain. Build it from every wave's `hitl` items, not only your own.

## L6. Finish last

A finished wave does not exit on its own - an interactive session sits at its prompt forever - so "no wave running" is never something `ListAgents` will tell you. The finish condition is yours to compute: **every wave in the chain has sent `landed`, or been declared dead twice.** Then, in this order:

1. Dispatch one final merge agent to run the full gates on the chain branch and report in the L4 shape.
2. **Audit the whole chain**: `~/.claude/skills/wave-chain/scripts/gh-audit.sh <chain#>`. Fix every `FAIL` on GitHub yourself - a ticket a dead wave left `in-progress`, a closed ticket without its evidence comment, a wave PR still open, an unticked checklist line - and rerun until `AUDIT PASS`. You do not finish on a `FAIL`, and you do not hand a `FAIL` to the owner as a to-do.
3. **Review the whole chain PR once**, where the waves' changes meet: dispatch one `opus` review subagent with the chain PR number and this brief - review the full diff of the PR for correctness bugs and for changes from different waves that contradict each other, post each real finding as an inline PR comment with the file and line, ignore style, and return only `review: <n> findings, <m> blocking`. Every blocking finding goes through a merge agent as a fix on the chain branch, then gates and smoke again, then the audit in step 2 reruns. You do not mark the PR ready with a blocking finding open; the owner opens a PR that has already been reviewed once, with the review visible on it.
4. Fill the `## Waiting on Kourosh` section of the chain PR body with every `parked-human` ticket and its one-line reason.
5. **If that section is not empty, build the §H decisions sheet now**, as part of this close-out, with every open `hitl` item on it - the owner answers it in one sitting and re-runs `--implement`; the next lead finds the answers in the inbox file.

Then mark the chain PR ready for review with a body that lists every ticket it closes and every wave PR it absorbed, kill the dev server you started (`lsof -ti:3000 | xargs kill`) - you are the only session allowed to, and this is the only moment, and give the owner one final summary that is built from the audit output and the chain PR, not from memory: per wave, tickets closed and not, elapsed time since the L2 comment, the one PR link with its preview deployment URL if the PR checks expose one, and the path of the decisions sheet if one was built. Every line in that summary points at something already on GitHub. **Never merge the chain PR.** Merging into `main` is the owner's click, after his preview.

## L7. Hand over before you get dumb

A lead that has been compacted is running on a summary of itself, and every message it handles from then on is billed against a long, lossy context. Hand over instead. Two triggers, whichever comes first: your context contains a "Conversation summary" block (you were compacted), or you have posted forty event lines on the chain issue since your L2 comment.

1. Post `lead-handover: <your session name> -> pending` on the chain issue, with the live state under it, read from the chain issue and the PR - not from memory: which waves are live with their pane ids, which are launched-and-landed, which not yet launched, the dev server pid, open `hitl` items.
2. Launch the successor in a new tab: `~/.claude/skills/wave-chain/scripts/launch-waves.sh <chain#> lead lead <repo-dir> <gen>`, where gen is 2 for the first handover, 3 for the next. It starts `claude --name wc<chain#>-lead-<gen> --autocompact 450k --model opus '/wave-chain --implement'` and the skill's L1 sees the open handover comment and resumes instead of re-cutting a branch.
3. Wait for the successor's `lead:` comment. Then `SendMessage` every live wave: `lead is now <successor name>`. A wave reports to a session name, and one still using yours reports into the void.
4. Comment `lead-handover: done -> <successor>` and stop. The branch, the PR, the dev server, and the tabs belong to nobody; the successor inherits them by reading the chain issue.

On the receiving side (a lead started with an open `lead-handover` comment): skip L1's branch and server steps, take the pane ids and state from the handover comment, post your own `lead:` line, and carry on from L4. A wave always sends to the **latest** `lead:` comment on the chain issue - §I6 re-reads it before each message, which is one `gh` call and makes a missed step 3 harmless.

---

# §H Human

One session owns the decision sheet. When the chain has a lead (§L), the lead owns it for the whole run and it never moves. Otherwise it is the orchestrator of the **lowest-numbered wave still running**. Every other orchestrator contributes through the chain issue and never writes that file. N sheets or N chat pings defeat the whole point.

Without a lead, ownership does not transfer by itself. Before you finish your wave, hand the sheet over: `SendMessage` the next lowest wave still running, and say on the chain issue who owns it now. An orchestrator that exits quietly leaves the sheet ownerless and every pending question unasked.

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
5. **Message that wave's orchestrator.** `SendMessage`, with the ticket number and its blockers. **This is the step that matters.** That session computed its frontier before your ticket existed and will never recompute on its own - a label alone is invisible to it. If that wave has already finished, say so and hand the ticket to the lowest wave still running instead. With a lead, copy the same message to the lead, so its final summary and its dead-wave check know the ticket exists.

## Project conventions

These are this project's; replace them with your own repo's when adapting the skill. Ticket bodies carry `## Done when` (the acceptance contract), often `## Options` with an orchestrator recommendation, `## Evidence`, and `## Build slot`. Labels: `wayfinder:task` on work, `wayfinder:map` on the map, `wave:N`, `hitl`, `in-progress`, `orchestrator`, `needs-info`.

From `build-waves.md`, the rules that bite: serialized files (`proxy.ts`, `app/layout.tsx`, `vercel.json`, `AGENTS.md`, `DESIGN.md`, `app/sitemap.ts`, `lib/account/data.ts`) are handed **up** to the orchestrator, never edited by a worker; migration timestamps are assigned at dispatch, not discovered at merge; any ticket that moves money gets an Opus-level review pass; a dead worker is resumed with `SendMessage`, never re-dispatched; Persian is never invented - propose it on the issue and ship approved strings verbatim, no hamza; gates are `npm run typecheck && npm run lint && npm test && npm run build`.

## Red flags - stop

- "My wave is blocked" → waves do not block. One ticket does. Run the other fifteen.
- "I'll check the chain issue's status column" → there is none, by design. Query the edges.
- "The blocker's agent said it's done" → verify the edge before starting.
- "The docs say this one shipped" → docs are not evidence. `file:line` or it stays open.
- "This one is obviously dead, I'll close it while reading" → `--read` writes nothing. Recommend it; `--modify` closes it.
- "He typed wave-chain, that's the confirm" → it is the request for the brief. The word is `confirm`, after the brief.
- "The brief is long, I'll describe the waves not the tickets" → one line per ticket. He is deciding what runs.
- "I'll write the labels, he'll say if the cut is wrong" → the cut is confirmed before the first write, not after the fiftieth.
- "I'll tell him about the hitl ticket when I reach it" → too late. Claim time.
- "I'll write my own decisions sheet" → one sheet, one owner, lowest live wave.
- "I labelled the new ticket, they'll pick it up" → they will not. The frontier was already computed. Message them.
- "Twelve free tickets, twelve agents" → five in flight, per wave. Queue the rest.
- "Port 3000 is busy, I'll take 3001" → that is a second dev server. The one that answered is the shared one; use it.
- "I'm done, I'll kill the dev server" → you did not start it, or someone else is still on it. Leave it up.
- "Port 3000 is empty, I'll start the server" (in a wave, with a lead) → you never start one. Message the lead; it started one and it is down.
- "I'll pick up a ticket from another wave" → you own one wave. Announce and hand over.
- "I'll close the tickets after the PR merges" → close them now. Nobody else will.
- "I'll run the other waves as subagents" → they need worktrees, budgets, and names. Sibling sessions, via the launcher.
- "wezterm cli failed, I'll open Terminal.app" → no. Report it and stop. WezTerm tab or nothing.
- "The owner can read the wave tabs himself" → he opened one session on purpose. Every report routes through the lead.
- "I'm the lead, I'll run wave 1 myself while I wait" → the lead runs nothing. Wave 1 is a tab.
- "Gates are green, no need to hit the route" → green gates have shipped blank pages. Smoke is a verdict line, not optional.
- "Each ticket was reviewed, the PR is reviewed" → each reviewer saw one ticket. The chain PR gets one review as a whole.
- "It's a small PR, I'll merge it here" → merge agent, fixed verdict. A diff in the lead's context is a diff it carries for hours.
- "I'll paste the failing output in the message" → comment it on the ticket, message the number.
- "I remember which waves are done" → after compaction you do not. The chain issue does.
- "All waves are done, I'm done" → the lead finishes last: final gates, PR ready for review, reap, summary.
- "Six waves, six tabs" → three live at once. Launch into freed slots.
- "ListAgents still shows wave 2, so it isn't done" → it sent `landed`; a finished tab never exits. You close it. Finish on `landed` lines, not on ListAgents.
- "I've been compacted but I remember enough" → you remember a summary. Hand over (§L7).
- "The tree has a few uncommitted files, I'll branch anyway" → those files ride the chain branch into the owner's PR. Stop and report.
- "I'll open my PR against main, it's cleaner" → with a lead, the base is the chain branch. One PR for the owner, and it is the lead's.
- "I'll tell him the details in chat, the PR is fine" → the PR is the deliverable. Write it there; the chat repeats it.
- "I closed them all, no need to run the audit" → memory is not state. The audit runs, and `landed` carries `audit: pass`.
- "The audit fails on a ticket that isn't mine" → with a lead, every FAIL at L6 is the lead's. Fix it.
- "The gates are green, I'll merge the chain PR" → never. The owner merges into main after his preview.
- "I'll branch from main, the chain branch is just wave 1's stuff" → it is every wave's stuff, including your blocker's. Base on the chain branch.
