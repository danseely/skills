---
name: transfer
description: Drop or pick up a transfer document so a fresh agent session can continue work. Use "drop" to compact the current conversation into a timestamped handoff file in a global store; use "pick up" to read the most recent transfer and resume — works across projects. Trigger phrases include "drop a transfer", "hand this off", "save my progress", "pick up where I left off", "resume the last session", "/transfer drop", "/transfer pickup".
argument-hint: "drop | pickup  (optionally: what the next session will focus on)"
---

# Transfer

Move working context between sessions. Two modes:

- **drop** — compact this conversation into a timestamped transfer document.
- **pickup** — read the most recent transfer and continue the work.

Transfers are stored in one **global store** (`~/.claude/transfers/`), shared across every project — so you can drop in one repo and pick up in another.

## Choosing the mode

1. **If an argument is given**, the first token decides the mode:
   - `drop`, `save`, `write`, `out` → **drop**
   - `pickup`, `pick-up`, `resume`, `continue`, `in` → **pickup**
   - Any remaining argument text is the focus/purpose for the next session (drop) or a note about what to resume (pickup).
2. **If no argument is given**, infer from the user's phrasing ("hand this off" → drop, "where did I leave off" → pickup).
3. **If still ambiguous**, ask the user: "Drop a new transfer, or pick up the most recent one?"

## Locating the transfers directory

Transfers live in one global store, shared across every project:

```sh
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/transfers"
```

On **drop**, create the directory if needed (`mkdir -p "$dir"`).

Layout:

```
~/.claude/transfers/
  transfer-YYYY-MM-DD-HHMMSS.md   # pending drops (not yet picked up)
  archive/                        # consumed drops (already picked up)
    transfer-... .md
```

A transfer is **pending** while it sits directly in the store, and **consumed** once a pickup has read it and moved it into `archive/`. Pickup always takes the newest pending file across the whole store, regardless of which project you're in — so each drop records its **origin** (see the template) to keep a global pile legible.

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
5. **Record the origin** — the repo or directory this drop came from — so a global store stays legible:

   ```sh
   origin="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
   ```
6. Write the transfer document to `$file` using the template below.
7. **Do not duplicate** content already captured elsewhere (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.
8. **Redact** anything sensitive — API keys, passwords, tokens, PII.
9. Report the path written and a one-line summary of what was captured.

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
- **Origin:** <repo name or working dir the drop came from>
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

   - If neither exists, tell the user there are no transfers in the store and stop.
3. Read `$latest`. Summarize for the user: when it was written (from the filename timestamp), its **Origin** (which project it came from — relevant now that the store is global), the stated **Purpose**, and the **Next steps**. (Don't block on confirmation — just summarize and proceed, unless the user asked to choose.)
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

If the user indicates the latest isn't the one they want, list available transfers (pending first, then archived) newest-first **with their origin and purpose**, since a global store mixes projects together:

```sh
for f in $(ls -1 "$dir"/transfer-*.md "$dir"/archive/transfer-*.md 2>/dev/null | sort -r); do
  printf '%s\n' "$f"
  grep -E '^\- \*\*(Origin|Purpose):\*\*' "$f"
done
```

Then let the user choose by origin/purpose rather than guessing from the timestamp alone.
