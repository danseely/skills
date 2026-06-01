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
   - Any remaining argument text is the focus hint for the next session (drop) or a note about what to resume (pickup).
2. **If no argument is given**, infer from the user's phrasing ("hand this off" → drop, "where did I leave off" → pickup).
3. **If still ambiguous**, ask the user: "Drop a new transfer, or pick up the most recent one?"

## Locating the transfers directory

Resolve the project root, then use `<root>/.claude/transfers/`:

```sh
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
dir="$root/.claude/transfers"
```

On **drop**, create the directory if needed (`mkdir -p "$dir"`).

Suggest the user add `.claude/transfers/` to `.gitignore` if these shouldn't be committed (they usually shouldn't — they're scratch context, not source).

## Drop

1. Resolve the transfers directory (above) and `mkdir -p` it.
2. Build a timestamped filename so pickup can always find the newest:

   ```sh
   ts="$(date +%Y-%m-%d-%H%M%S)"
   file="$dir/transfer-$ts.md"
   ```

   The `YYYY-MM-DD-HHMMSS` format sorts lexicographically by recency, so the last file by name is the newest even if mtimes drift.
3. Write a transfer document to `$file` covering:
   - **Focus** — what the next session should work on (use the argument hint if provided).
   - **Current state** — what's done, what's in progress, what's blocked.
   - **Key context** — decisions made and why, gotchas, things a fresh agent would otherwise have to rediscover.
   - **Next steps** — concrete, ordered actions to pick up.
   - **Suggested skills** — skills the next agent should invoke for this work.
4. **Do not duplicate** content already captured elsewhere (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.
5. **Redact** anything sensitive — API keys, passwords, tokens, PII.
6. Report the path written and a one-line summary of what was captured.

## Pickup

1. Resolve the transfers directory (above).
2. Find the most recent transfer:

   ```sh
   latest="$(ls -1 "$dir"/transfer-*.md 2>/dev/null | sort | tail -n 1)"
   ```

   If none exist, tell the user there are no transfers for this project and stop.
3. Read `$latest`. Briefly summarize for the user: when it was written (from the filename timestamp), the stated focus, and the next steps.
4. Invoke any skills listed in its "Suggested skills" section that are relevant.
5. Continue the work from where the transfer left off. If a resume note was passed as an argument, prioritize that.

### Picking an older transfer

If the user indicates the newest isn't the one they want, list the available transfers newest-first with their timestamps and let them choose:

```sh
ls -1 "$dir"/transfer-*.md 2>/dev/null | sort -r
```
