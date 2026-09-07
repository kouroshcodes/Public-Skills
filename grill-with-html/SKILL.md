---
name: grill-with-html
description: A relentless interview to sharpen a plan or design, where wide rounds are rendered as an interactive HTML round sheet and the settled decisions land in CONTEXT.md and ADRs.
disable-model-invocation: true
---

# grill-with-html

Run `mattpocock-skills:grilling` and `mattpocock-skills:domain-modeling` together, as `grill-with-docs` does, plus `html-it` for the round sheet. Call the Skill tool for all three before the first round.

Grilling owns the interview. Domain-modeling owns `CONTEXT.md` and `docs/adr/`. This skill only adds **when the round becomes HTML instead of terminal text**, and what that HTML must contain.

## When a round goes to HTML

Render the round sheet when **either** is true:

- The frontier has **4 or more** questions
- The choices are comparative — options that only make sense seen side by side (schemas, API shapes, state models, layouts)

Otherwise ask the round in the terminal as plain grilling does. A three-question round costs more to render than to answer; don't pay it.

Never render the *final* confirmation ("have we reached shared understanding?") as HTML. That's one question and it belongs in the conversation.

## The round sheet

One file, **regenerated at the same path every round** — the user keeps a single browser tab and refreshes. Write it to the scratchpad directory, or a gitignored path in the project. State the path once, in round 1; after that just say "refreshed — round N is up."

Build it at html-it **Level 3**. Three sections, in this order:

**1. Settled** — every decision already answered, as static text. Question, the answer landed on, and one line of why. Not interactive: settled is settled. This is the memory that terminal scrollback loses by round four.

**2. This round** — one card per frontier question. Grilling attaches a recommended answer to every question; that recommendation is the **pre-selected state**. The sheet must open in a valid state where hitting Copy immediately means "accept all recommendations."

- Multiple choice → inline pick cards, one pick per group, recommendation carrying `.picked` on load
- Open-ended → a `<textarea>`, prefilled with the recommendation
- Every card also gets a free-text override field, multiple-choice included. Real answers are "B, but only for the write path."

**Never put a question in a `placeholder` attribute.** Placeholder text sits in an empty box, renders grey, and disappears the moment the field is focused — readers skip it entirely. If you want an answer to something, it gets its own card in the frontier. If it doesn't deserve a card, it isn't a question and you don't need the answer. Placeholders are for showing the shape of a reply, never for asking. A question asked three rounds running in a placeholder is a question you never asked.

**3. Blocked** — downstream questions, greyed, each labelled with the open question it waits on. This is the design tree's frontier made visible.

End with the mandatory export button: **`Copy as answers`**, emitting one `Q<n>: <answer>` block per question, override text appended where present. The user pastes it straight back into the terminal.

### Clipboard on file:// URLs

`navigator.clipboard` is unreliable on `file://` pages. A silently dead Copy button breaks the whole loop, so always ship the fallback:

```js
function copyText(text) {
  if (navigator.clipboard?.writeText) {
    return navigator.clipboard.writeText(text).catch(fallback);
  }
  return fallback();
  function fallback() {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }
}
```

If both paths fail, the sheet must still expose the raw export text in a selectable `<textarea>` so the round is never a dead end.

## When a question needs a prototype instead of an answer

Some questions cannot be settled by asking. The answer exists, but neither of you can see it from the armchair — "does this state machine need four states or six", "does this interaction feel right". Discussion produces confident guesses on both sides and settles nothing.

That is a fact that doesn't exist yet and has to be manufactured. Grilling already has the slot for it: a running exploration is an unsettled prerequisite, and only the questions downstream of it wait. A prototype occupies that slot. Invoke `mattpocock-skills:prototype` **lazily**, only when the gate below fires — it is deliberately not in this skill's opening Skill calls, because most sessions never need it and every session would pay for it.

### The gate

**Ask: can you name, in advance, the result that would change your mind?**

If yes, the question is empirical and a prototype earns its cost. If no, it's a preference — build the thing and the user picks what they already wanted, having spent an hour to arrive there. Prototyping a preference is theater.

Most frontier questions fail this test. Judgment calls, trade-offs, and anything whose options differ by *what you value* rather than *what happens* are answered by asking. Be strict: the gate should fire a handful of times across a whole session, or not at all.

Two more conditions, both required:

- **The decision is expensive to reverse.** A cheap decision is cheaper to make wrong and fix.
- **Ninety seconds of clicking would actually settle it.** If the prototype needs to be substantial to answer anything, the question is too big and wants splitting first.

### Never block a round on it

Grilling does not stall. When the gate fires, start the prototype and **ask the rest of the frontier in the same round** — the prototype-dependent question drops to the next one, listed in Blocked as `waits on prototype: <what it answers>`. Say in one line what's being built and what it will settle.

### Put it in the card

Prototype's logic branch produces a single self-contained HTML file a non-developer can drive. The round sheet is already that. So don't hand the user a second file to open separately — **embed the prototype inside the question card it answers.**

The reader sees the question, drives the working thing, and picks an answer without leaving the page. Keep the prototype's own state in the DOM, keep it visibly a prototype rather than a polished component, and leave the card's pick-options and override field exactly as they are underneath it. The toy informs the answer; it doesn't replace the question.

### Half of prototype's rules assume a codebase

Prototype tells you to place code next to the module it prototypes for, run it from the project's task runner, fold validated decisions into real code, and commit the prototype to a throwaway branch. That applies when the grilling session is about software in a repo.

It does not apply when it isn't. This skill gets used to design things that aren't code — a business, a process, a launch. There, ignore the placement, task-runner, and branch-capture rules entirely: the prototype is a scratch HTML file in the scratchpad, and the only thing worth capturing is the answer it produced, which belongs in the round's Settled section like any other decision.

## Docs stay markdown

`html-it` says stop reaching for markdown. It does not win here. `CONTEXT.md` and `docs/adr/*.md` are the source of truth — diffable, git-tracked, and read by agents in future sessions. Write them exactly as `domain-modeling` specifies, inline, the moment a term or decision settles.

HTML is the *view*, generated from them. Never the store.

## At the end

Once the frontier is empty and the user confirms shared understanding, build a single rollup page: the glossary, the ADRs written this session, and the finished design tree. The per-round sheets stay local and disposable; this one is the deliverable.

It goes to **two destinations, always both**:

1. **Published as an Artifact** — the shareable link.
2. **Saved to disk beside the markdown**, as `design-record.html` in the same directory as `CONTEXT.md`. The user keeps the whole record in one folder, and it survives without a network or an account.

Do both without being asked. Load `artifact-design` before writing it, and `artifact-diagramming` if the tree earns a diagram.

### The saved copy needs a document wrapper

The Artifact runtime supplies `<!doctype>`, `<html>`, `<head>`, charset and viewport at publish time, so the file you wrote for publishing has none of them. Copied to disk as-is it is a fragment, and a browser opening it guesses the encoding.

Wrap the same content when saving locally:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>:root{color-scheme:light dark}body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>
<!-- the published file's content, verbatim -->
</body>
</html>
```

**The charset line is not optional.** Without it a local browser mis-decodes every non-ASCII character in the page — non-Latin scripts, em-dashes, curly quotes. A design record that renders correctly at its URL and turns to mojibake on disk is worse than no local copy, because the user finds out later.

### Say what the local copy can't do

Google Fonts load over the network. Offline, the saved page falls back to system faces — readable, plainer. Mention it in one line and offer to inline the fonts as data URIs if they need it genuinely offline; don't do it unasked, since it inflates the file by roughly a megabyte.

Also say plainly that the two files do not sync. The markdown stays the source of truth; the HTML is a snapshot of it as of that moment, and so is the published Artifact.
