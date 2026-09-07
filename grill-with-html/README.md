# grill-with-html

A Claude Code skill that interviews you about a plan until there's nothing left silently assumed — rendering each round as an interactive HTML sheet, and writing what you settle into a glossary and ADRs as you go.

It composes three existing skills and adds the one thing they don't have on their own: **when a round becomes a page instead of a wall of terminal text, and what that page has to contain.**

---

## Why

Interrogating a design in the terminal works, but it has two failure modes.

By round four you've lost track of what you already decided. It's all scrollback, and re-reading it costs more than re-deciding.

And a round of six questions, each with a recommendation attached, is a lot to answer by hand. So you type *"yeah, all your recommendations"* — which is fast and lossy, because you didn't actually read four of them.

An HTML round sheet fixes both. Settled decisions stay visible at the top with their reasoning. Each open question is a card with the recommendation **pre-selected**, so agreeing is one click and the accurate path is also the cheap one. You hit `Copy as answers` and paste back into the terminal.

---

## What a round looks like

```
┌─ SETTLED ─────────────────────────────────────────────┐
│  Capital      $0 upfront, funded from revenue         │
│               Caps growth rate; doesn't block starting │
│  Logging      No-logs by design                        │
│               Traffic counters only. ADR 0001.         │
└────────────────────────────────────────────────────────┘

┌─ THIS ROUND ──────────────────────────────────────────┐
│  Q1  Payment rails                                     │
│      ● Crypto only            [recommended]            │
│      ○ Card-to-card via a person in-country            │
│      ○ Through resellers                               │
│      ┌ Override / detail ─────────────────┐            │
│      └────────────────────────────────────┘            │
└────────────────────────────────────────────────────────┘

┌─ BLOCKED ─────────────────────────────────────────────┐
│  Pricing & tier boundaries    waits on Q1, Q3          │
│  Anti-blocking ops cadence    waits on protocol stack  │
└────────────────────────────────────────────────────────┘

                                     [ Copy as answers ]
```

Three sections, one file, regenerated at the same path every round — you keep one browser tab and refresh.

---

## Install

Three dependencies, two of them required.

**1. The `mattpocock-skills` plugin** — provides `grilling` and `domain-modeling`, which do the actual interviewing and documentation.

```
/plugin
```
Then install `mattpocock-skills` from the official marketplace.

**2. The `html-it` skill** — provides the four-level HTML output framework the round sheet is built on.

```bash
git clone https://github.com/robonuggets/html-it ~/.claude/skills/html-it
```

**3. This skill.**

```bash
git clone https://github.com/kouroshcodes/grill-with-html ~/.claude/skills/grill-with-html
```

`prototype` (also in `mattpocock-skills`) is optional — invoked lazily, only when a question turns out to be empirical rather than a matter of judgment.

---

## Use

```
/grill-with-html should we migrate the write path to an event log?
```

It runs `disable-model-invocation: true`, so it only ever fires when you type it.

Each round: it computes the frontier — every decision whose prerequisites are already settled — and asks all of it at once. Your answers reshape the tree and push the frontier outward. The session ends when the frontier is empty and you confirm you've reached shared understanding.

---

## What you end up with

| Output | Where | What it's for |
|---|---|---|
| Round sheet | scratchpad, one file, regenerated | Driving the interview. Disposable. |
| `CONTEXT.md` | project root | Glossary. Terms only, no decisions. |
| `docs/adr/*.md` | project | Decisions that were hard to reverse, surprising, and a real trade-off. |
| `design-record.html` | beside `CONTEXT.md` | The whole record as one page. |
| Published Artifact | claude.ai | Same page, shareable link. |

**Markdown stays the source of truth.** `html-it` opens with *"stop reaching for markdown"* — this skill overrules it for `CONTEXT.md` and the ADRs, because those are diffable, git-tracked, and read by agents in future sessions. The HTML is the view, never the store.

---

## The rules it encodes

Most of these came out of running the thing and finding out.

**A round only becomes a page when it's worth it.** Four or more questions on the frontier, or choices that only make sense seen side by side. A three-question round costs more to render than to answer, and the final *"have we reached shared understanding?"* belongs in the conversation, never in a file.

**Never put a question in a `placeholder` attribute.** Placeholder text is grey, sits in an empty box, and vanishes on focus. Readers skip it entirely. In the first real session the same question got asked three rounds running that way and was never once seen. If it deserves an answer it gets a card; if it doesn't deserve a card, you didn't need the answer.

**Every card gets a free-text override, multiple-choice included.** Real answers are *"B, but only for the write path."* Twice in one session the pre-selected pick was left untouched while the override underneath said something that contradicted it outright — and the override was the real answer both times.

**`navigator.clipboard` is unreliable on `file://`.** A silently dead Copy button kills the loop, so the fallback ships with the skill, and the raw export text is always exposed in a selectable textarea so a round can't dead-end.

**The saved copy needs a document wrapper.** The Artifact runtime supplies `<!doctype>`, `<head>`, charset and viewport at publish time — so the file you wrote for publishing is a fragment. Copy it to disk unchanged and the browser guesses the encoding. Without `<meta charset="utf-8">`, every non-Latin character in the page breaks locally while rendering perfectly at its URL, which is the worst way to find out.

**Prototype only what's empirical.** Can you name, in advance, the result that would change your mind? If not, it's a preference, and building something to settle a preference is theater. The gate should fire a handful of times in a whole session, or not at all.

---

## Credits

This is a wrapper. The parts that do the work belong to other people.

- **[Matt Pocock](https://github.com/mattpocock)** — `grilling`, `domain-modeling`, and `prototype`, from [`mattpocock-skills`](https://github.com/mattpocock/skills). The design-tree-and-frontier model, the ADR discipline, and the rule that finding facts is the agent's job and decisions are the user's are all his.
- **[robonuggets](https://github.com/robonuggets/html-it)** — the `html-it` skill and its four-level framework.
- **[Thariq Shihipar](https://x.com/trq212)** — the original *Unreasonable Effectiveness of HTML* framework that `html-it` implements.

`grill-with-docs` in Matt's plugin already composes `grilling` + `domain-modeling`. This adds the HTML round sheet and the rules for when it's worth rendering one.

## License

MIT
