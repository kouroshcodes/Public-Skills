---
name: html-worklist
description: HTML worklist - turn a GitHub issue, a doc, a plan, or the tasks in this conversation into one self-contained HTML worklist on the Desktop, carrying a paste-ready prompt that makes a fresh session fan out parallel agents over the tasks and write progress back into the file. Use when the user wants work handed to another session, an issue broken into a runnable task board, tasks parallelised across agents, or asks for a worklist. [kourosh]
argument-hint: "issue number, file path, or nothing (uses this conversation)"
metadata:
  author: kourosh
---

Build one HTML file - the **worklist** - and drop it on the user's Desktop. It carries the tasks, the protocol for running them, and a prompt the user pastes into a fresh session. That session becomes the **runner**: it fans out parallel agents and writes every state change back into the same file. The file is the **ledger** - the thing the user looks at to know where the work stands.

You are building the ledger, not running it. The runner's rules live inside the generated file; do not restate them here or execute them now.

## 1. Gather the tasks

The source is whatever the user pointed at: an issue (`gh issue view <n> --json number,title,body,url`), a label query, a doc or queue file, a plan, or this conversation. Read the real source - never restate an issue from memory.

Split it into tasks an agent can finish alone. Done when every task carries:

- a stable id (`T1`, `T2`, …) and a one-line title
- the context an agent with **zero** conversation history needs to start
- the exact files and paths in play
- a checkable acceptance criterion - the runner has to be able to tell done from not-done without asking
- its issue number and URL, if it came from one

## 2. Find the collisions

Two tasks that write the same file cannot run at the same time. Done when every task is either marked parallel-safe or carries `data-blocked-by` naming every task that must land first, space-separated: `data-blocked-by="T1 T4"`.

## 3. Write the file

Read [`template.html`](template.html) and fill it. Write to `~/Desktop/worklist-<slug>-<YYYY-MM-DD>.html`, where `<slug>` is a short kebab-case name for the batch. Timestamp with `date "+%Y-%m-%d %H:%M %Z"`.

Done when the file exists at that path, every gathered task appears once as an `<article class="task">` with `data-state="todo"` and a unique `data-id`, and the prompt box holds that file's own absolute path.

## 4. Hand it over

Print the absolute path and the paste prompt verbatim, so the user can copy it straight out of the terminal:

```
Read <abs-path> and run it as the worklist runner - follow the RUN PROTOCOL inside the file.
```
