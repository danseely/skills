# `transfer`

Hand a working session off to a fresh one, and pick it back up — across any project.

Agent context windows have a usable "smart zone" that's far smaller than the advertised limit — past it, responses drift and degrade. The fix is to compress what matters into a small document and continue in a clean session. This skill makes that two-way: **drop** compacts the current conversation into a timestamped file in a global store (`~/.claude/transfers/`), and **pickup** reads the most recent one and resumes from it — even if you dropped it from a different repo.

Inspired by [mattpocock/skills/handoff](https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff), with a few deliberate changes: it's named `transfer`, it's bidirectional (drop *and* pickup, not write-only), and files carry a timestamp + lifecycle state so pickup always lands on the right one.

**NOTE:** this is separate from the `handoff` skill in this repo

[`handoff`](../handoff) is a durable, repo-anchored *state machine* for multi-session feature work (GitHub issues, checkpoints, drift checks). `transfer` is lighter: a disposable per-session briefing you drop and pick up. Use `handoff` to track a project over weeks; use `transfer` to move a single working context from one session to the next.

## What it does

- **Two modes.** `drop` writes a transfer document; `pickup` reads the latest and continues. Mode comes from an explicit `drop`/`pickup` argument, is inferred from your phrasing otherwise, and is asked for only when ambiguous.

- **Global storage.** Files live in one shared store, `~/.claude/transfers/`, so you can drop in one repo and pick up in another. Each file records its **origin** project to keep the shared pile legible.

- **Self-actuating files.** Every dropped file opens with a "read me first" preamble, so it works whether picked up by this skill or pasted straight into another agent (Codex, Copilot, a fresh Claude session).

- **Purpose is required.** A transfer is only as good as knowing what the next session is for, so `drop` won't write without a stated purpose — it asks if you didn't give one.

- **Pending vs consumed lifecycle.** A drop is *pending* until a pickup reads it, stamps `Picked up: <ts> (into <project>)`, and moves it into `archive/`. Pickup takes the newest *pending* file in the store, and falls back to the newest archived file when nothing's pending — the "didn't finish last time" case. Files are archived, never auto-deleted.

- **Audit trail (informational).** `Origin` records which project dropped a transfer and `Picked up` records which project later consumed it — a data-only trail, not a permission gate. Any pickup can read any pending transfer regardless of origin.

- **Boomerang lineage.** If a session that began with a pickup later drops again, the new file records `Continues: <prior file>` plus a "What changed since pickup" section, so round-trip chains (A → B → back to A) stay traceable.

- **Suggested skills, pointers not copies, redaction.** Each file lists skills the next session should invoke, references artifacts (PRDs, issues, commits) by path/URL instead of restating them, and strips secrets/PII before writing.

## When to use it

- You're approaching the context limit and want to continue clean instead of compacting in place.
- A side task surfaces mid-session that deserves its own pure session.
- You notice something in repo A that really belongs in repo B — drop it now, pick it up later from B.
- You want to spin off a prototype or an adversarial review in another agent and feed the learnings back.

## When to skip it

- One-shot tasks you'll finish in the same session.
- Durable, multi-week project tracking — reach for [`handoff`](../handoff) instead.

## Agnostic to agent and harness

The dropped file is plain markdown with a self-actuating preamble, so any SKILL-format runtime can drop it and any agent can consume it by reading the file. Mode-detection phrasing and the `/transfer` invocation are conveniences on top.

## Installing

See the [repo root README](../README.md#installing). The short version: drop or symlink the `transfer/` folder into your agent runtime's skills directory.

## What's in this folder

- [`SKILL.md`](./SKILL.md) — the canonical skill: frontmatter, mode detection, drop/pickup steps, file template, lifecycle rules. This is what the agent loads.
- `README.md` (this file) — human-facing overview.

## Conventions, in one place

| Convention | One-line summary |
|---|---|
| Global store | Files live in `~/.claude/transfers/`, shared across all projects; each records its origin. |
| Timestamped filenames | `transfer-YYYY-MM-DD-HHMMSS.md` sorts by recency, so newest-by-name is newest-by-time. |
| Purpose required | `drop` won't write without knowing what the next session is for. |
| Pending → consumed | Pickup stamps and archives the file it reads; never auto-deletes. |
| Audit trail | `Origin` + `Picked up` record which project dropped and consumed each transfer — info only, not a gate. |
| Self-actuating | Files open with a preamble so they work in any agent, not just via pickup. |
| Link, don't restate | Reference artifacts by path/URL; restated content rots. |
| Redact secrets before writing | Strip API keys, passwords, and PII from the transfer. |

## Status

In use for personal session-to-session work. Frontmatter is unversioned; behavior tracks `SKILL.md` on `main`.
