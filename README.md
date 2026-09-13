# Public Skills

Claude Code skills I've built and published. Each folder is a self-contained skill — a `SKILL.md` plus whatever it needs.

## Skills

### [`grill-with-html`](./grill-with-html)

A relentless design interview that renders each round as an interactive HTML sheet, and writes the glossary and ADRs as you go.

Composes `grilling`, `domain-modeling` and `html-it`, and adds the rule none of them have on their own: **when a round is worth rendering as a page instead of terminal text, and what that page has to contain.** Settled decisions stay visible with their reasoning, open questions arrive as cards with the recommendation pre-selected, and you export your answers back to the terminal with one button.

Requires the [`mattpocock-skills`](https://github.com/mattpocock/skills) plugin and the [`html-it`](https://github.com/robonuggets/html-it) skill.

### [`html-worklist`](./html-worklist)

Turns a GitHub issue, a doc, a plan, or the tasks in the current conversation into one self-contained HTML worklist on your Desktop.

The file is the **ledger**. It carries the tasks, the acceptance criteria, the collision map of which tasks can't run at the same time, and a paste-ready prompt. Drop that prompt into a fresh session and it becomes the **runner** — fanning out parallel agents across the tasks and writing every state change back into the same file, so one page always shows where the work stands.

No dependencies.

### [`wave-chain`](./wave-chain)

Runs many orchestrator sessions at once over one GitHub backlog — one wave each, unblocking each other by message — and hands you back **one PR**.

You open one session, type `/wave-chain --implement`, and leave. A lead session launches every wave in its own WezTerm tab, merges their PRs into one chain branch, audits that GitHub actually reflects the run, and gives you a single PR to preview. Waves decide who owns what; they are **not** barriers. The lock is per ticket, as GitHub's native `blockedBy` edges an agent can query, so a session with two blocked tickets runs its other fourteen instead of idling a whole wave. When a session closes a blocker it **messages** whoever was waiting, who re-verifies the edge before starting — no polling, no status column going stale. Questions that need you are surfaced at claim time and collected into one decision sheet rather than N interruptions.

Requires the [`superpowers`](https://github.com/obra/superpowers) plugin and WezTerm for lead mode.

---

## Installing a skill

Skills live in `~/.claude/skills/`. Clone this repo somewhere, then copy the one you want:

```bash
git clone https://github.com/kouroshcodes/Public-Skills
cp -r Public-Skills/grill-with-html ~/.claude/skills/
```

Or clone directly into place if you only want one and don't mind the extra repo:

```bash
git clone https://github.com/kouroshcodes/Public-Skills ~/.claude/skills/tmp \
  && mv ~/.claude/skills/tmp/grill-with-html ~/.claude/skills/ \
  && rm -rf ~/.claude/skills/tmp
```

Restart Claude Code if the skill doesn't appear immediately.

## License

MIT, per-skill. See each folder's `LICENSE`.
