---
name: transfer
description: Drop or pick up a project transfer document so a fresh agent session can continue work. Use "drop" to compact the current conversation into a timestamped handoff file; use "pick up" to read the most recent transfer for this project and resume. Trigger phrases include "drop a transfer", "hand this off", "save my progress", "pick up where I left off", "resume the last session", "/transfer drop", "/transfer pickup".
argument-hint: "drop | pickup  (optionally: what the next session will focus on)"
---

# Transfer

Move working context between sessions for the **current project**. Two modes:

- **drop** — compact this conversation into a timestamped transfer document.
- **pickup** — read the most recent transfer for this project and continue the work.

Transfers are stored per-project in `.claude/transfers/` (relative to the project root), so pickup only ever sees this project's transfers.

## Choosing the mode

1. **If an argument is given**, the first token decides the mode:
   - `drop`, `save`, `write`, `out` → **drop**
   - `pickup`, `pick-up`, `resume`, `continue`, `in` → **pickup**
   - Any remaining argument text is the focus/purpose for the next session (drop) or a note about what to resume (pickup).
2. **If no argument is given**, infer from the user's phrasing ("hand this off" → drop, "where did I leave off" → pickup).
3. **If still ambiguous**, ask the user: "Drop a new transfer, or pick up the most recent one?"

## Locating the transfers directory

Resolve the project root, then use `<root>/.claude/transfers/`:

```sh
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
dir="$root/.claude/transfers"
```

On **drop**, create the directory if needed (`mkdir -p "$dir"`).

Layout:

```
.claude/transfers/
  transfer-YYYY-MM-DD-HHMMSS.md   # pending drops (not yet picked up)
  archive/                        # consumed drops (already picked up)
    transfer-... .md
```

A transfer is **pending** while it sits directly in `.claude/transfers/`, and **consumed** once a pickup has read it and moved it into `archive/`. In normal use there is at most one pending file, which is what makes "pick up the latest" unambiguous.

Suggest the user add `.claude/transfers/` to `.gitignore` if these shouldn't be committed (they usually shouldn't — they're scratch context, not source).

## Drop

1. Resolve the transfers directory (above) and `mkdir -p` it.
2. **Establish the purpose.** A good transfer requires knowing what the next session is for.
   - Use the argument text if the user provided a focus/purpose.
   - **If no purpose was given, ask before writing:** "What will the next session focus on?" Do not write a transfer without a stated purpose — it is the single most important input.
3. **Check for lineage (boomerang).** If *this* session was itself started by a `pickup` earlier (you read and resumed a prior transfer), then this drop continues that chain. Note the basename of the file you picked up; you'll record it as `Continues:` and add a "What changed since pickup" section below.
4. Build a timestamped filename so pickup can always find the newest:

   ```sh
   ts="$(date +%Y-%m-%d-%H%M%S)"
   file="$dir/transfer-$ts.md"
   ```

   The `YYYY-MM-DD-HHMMSS` format sorts lexicographically by recency, so the last file by name is the newest even if mtimes drift.
5. Write the transfer document to `$file` using the template below.
6. **Do not duplicate** content already captured elsewhere (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.
7. **Redact** anything sensitive — API keys, passwords, tokens, PII.
8. Report the path written and a one-line summary of what was captured.

### Transfer file template

Write the file with this structure. The preamble at the top makes the file **self-actuating** — it works whether picked up by this skill or pasted directly into any other agent (Codex, Copilot, a fresh Claude session).

```markdown
> **Resuming work — read me first.** You are a fresh agent picking up an
> in-progress task. Read this whole document, invoke the skills under
> "Suggested skills," then continue from "Next steps." Treat this as your
> initial briefing. If anything here conflicts with the current repo state,
> trust the repo and note the drift.

# Transfer: <short title>

- **Created:** <YYYY-MM-DD HH:MM:SS>
- **Purpose:** <what the next session is for>
- **Continues:** <prior transfer filename, or "none">
- **Picked up:** (pending)

## Focus
What the next session should work on.

## Current state
What's done, what's in progress, what's blocked.

## Key context
Decisions made and why, gotchas, things a fresh agent would otherwise
have to rediscover. Reference artifacts by path/URL rather than pasting them.

## Next steps
Concrete, ordered actions to pick up.

## Suggested skills
Skills the next agent should invoke for this work.

## What changed since pickup
(Only if "Continues" is set.) What this session did on top of the transfer
it resumed — so the chain stays traceable back to the parent.
```

## Pickup

1. Resolve the transfers directory (above).
2. Find the most recent **pending** transfer (top level only, not `archive/`):

   ```sh
   latest="$(ls -1 "$dir"/transfer-*.md 2>/dev/null | sort | tail -n 1)"
   ```

   - If a pending file exists, use it.
   - If none are pending, fall back to the newest **consumed** one and say so (this is the "I didn't finish last time" case):

     ```sh
     latest="$(ls -1 "$dir"/archive/transfer-*.md 2>/dev/null | sort | tail -n 1)"
     ```

   - If neither exists, tell the user there are no transfers for this project and stop.
3. Read `$latest`. Summarize for the user: when it was written (from the filename timestamp), the stated **Purpose**, and the **Next steps**. (Don't block on confirmation — just summarize and proceed, unless the user asked to choose.)
4. **Mark it consumed.** Stamp the header and archive it so it won't be picked up again and cruft stays contained:

   ```sh
   ts="$(date +%Y-%m-%d-%H%M%S)"
   # edit the file: replace "Picked up: (pending)" with "Picked up: <ts>"
   mkdir -p "$dir/archive" && mv "$latest" "$dir/archive/"
   ```

   (Files are archived, never deleted. Prune `archive/` by hand whenever you like.)
5. **Remember the lineage.** Note the basename of the file you just picked up. If you later `drop` in this same session, record it as `Continues:` and fill in "What changed since pickup" so the boomerang chain stays traceable.
6. Invoke any skills listed under "Suggested skills" that are relevant.
7. Continue the work from where the transfer left off. If a resume note was passed as an argument, prioritize that.

### Picking an older transfer

If the user indicates the latest isn't the one they want, list available transfers (pending first, then archived) newest-first and let them choose:

```sh
ls -1 "$dir"/transfer-*.md "$dir"/archive/transfer-*.md 2>/dev/null | sort -r
```
