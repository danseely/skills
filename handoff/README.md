# `handoff`

Durable project state for agent work that outlives a single session.

Long-running tasks lose to context churn: a fresh session reads the chat scrollback if it's lucky, re-derives the goal from `git log` and code, and quietly drifts off the plan. This skill gives the agent a small, disciplined state machine over an **external store** — a GitHub issue, a repo doc, or a branch-local scratch file — so the next session can pick up exactly where the last one left off, with the goal, the next action, and the dead-end list intact.

> **Not the same as the conversation-compaction skill of the same name** (e.g. [mattpocock/skills/handoff](https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff)). That one summarizes a single conversation to a temp file for the next agent. This one maintains durable, repo-anchored state across many sessions, with explicit checkpoints, drift checks, and named evidence for "done."

## What it does

- **State machine over an external store.** Every session begins in `orient`, then moves through `work → checkpoint → done`, with `blocked` as an off-ramp. The store — not the chat — is canonical.

  ```
                   ┌─── session boundary ───┐
                   ↓                        │
  orient ──→ work ──→ checkpoint ──→ done ──┘
     │         │           │
     └────→ blocked ←──────┘
                │
                └──→ work (after resolution)
  ```

- **Picks storage by context.** Preferred: a GitHub issue (body = current state, comments = append-only log). Falls back to `docs/project-state.md`. Allows `.handoff/` scratch files for autonomous runs only.

- **A fixed checkpoint schema.** Every handoff comment is a known shape, so the next session finds *current branch, what changed, validation run, next action, and any drift* without rereading the thread.

- **A small status vocabulary** for features and acceptance criteria — `not_started / in_progress / blocked / passed / dropped` — with a hard rule that `passed` requires named evidence (a test, a commit, an inspected behavior), not a completion claim.

- **Mandatory startup smoke test.** No new work on a broken baseline. Either fix it or surface a blocker.

- **Append-only Dead Ends** and **decisions log.** Past attempts and reversed decisions don't get re-litigated — and don't get edited in place.

- **Explicit drift check** before substantial implementation: is the current task still serving the active goal, or has scope crept?

## When to use it

- Multi-session feature work where the next session might be tomorrow, next week, or a different agent.
- Anything with a non-trivial acceptance-criteria list or a sequence of dependent steps.
- Work where a human reviewer wants a clear "where are we now?" answer between sessions.

## When to skip it

- One-shot tasks. A bug fix you'll finish in the same session doesn't need a state machine.
- Pure conversation summarization. Use a lighter compaction skill for that.

## Agnostic to agent and harness

Nothing in here is Claude-specific. The skill references `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, etc. as equivalent "agent marker files," and the optional `./agent-bootstrap` / `./agent-check` scripts are runtime-neutral. Tested in Claude Code and Codex; should work in any harness that loads SKILL-format skills.

## Installing

See the [repo root README](../README.md#installing). The short version: drop or symlink the `handoff/` folder into your agent runtime's skills directory.

## What's in this folder

- [`SKILL.md`](./SKILL.md) — the canonical skill: frontmatter, state machine, storage ladder, templates, rules. This is what the agent loads.
- `README.md` (this file) — human-facing overview.

## Conventions, in one place

These are scattered throughout `SKILL.md` but worth listing up front:

| Convention | One-line summary |
|---|---|
| Test ratchet | Never weaken or remove tests to make a check pass. |
| Startup smoke test | Don't start a session on a red baseline. |
| `passed` needs evidence | A claim isn't evidence; a test/commit/inspected behavior is. |
| Append-only decisions | Plan changes are recorded, not edited in place. |
| Append-only Dead Ends | Failed approaches are written once and never rewritten. |
| Redact secrets before writing | Issue comments are public — strip tokens/PII from checkpoints. |
| Link, don't restate | Reference PRDs/ADRs/commits by path or URL; restated content rots. |

## Status

Used in production for personal multi-session work since v0.2. Frontmatter currently at **v0.3** (renamed from `planning-handoff` to `handoff`; behavior unchanged).
