---
name: planning-handoff
description: This skill should be used when the user asks for "planning-handoff", "handoff", "project state", "status state", "long-running project memory", or "resume context". Also use automatically for multi-session project work, planning checkpoints, project-state capture, feature ledgers, drift detection, or any task likely to span enough scope that chat context may be lost.
version: 0.2.0
---

# Planning Handoff

Use this skill when work needs durable project state outside chat. Skip it for one-shot tasks unless the user explicitly asks for a handoff or planning artifact.

The skill runs as a small state machine over an external store. The harness — bootstrap script, check script, and state store — is canonical. Repo files and chat narrative are not.

## State Machine

Every session begins in `orient`. From there, work flows through four named states. After `done`, the next session re-enters `orient` with the next goal.

```
                 ┌─── session boundary ───┐
                 ↓                        │
orient ──→ work ──→ checkpoint ──→ done ──┘
   │         │           │
   └────→ blocked ←──────┘
              │
              └──→ work (after resolution)
```

| From | To | Trigger |
|---|---|---|
| (new session) | `orient` | Session start, including the session after a `done` |
| `orient` | `work` | Bootstrap passed; active goal confirmed against issue body or `docs/project-state.md` (in autonomous mode, against the most recent checkpoint's `Next action`); smoke test green or explicitly recorded as N/A |
| `orient` | `blocked` | Bootstrap or smoke test fails; baseline is not trustworthy |
| `work` | `checkpoint` | Feature status changed, or any irreversible action imminent. Soft heuristic: roughly 5+ tool-using steps since the last checkpoint, when countable |
| `work` | `blocked` | Blocker discovered mid-work; record and stop before next tool call |
| `checkpoint` | `work` | State written, next action confirmed |
| `checkpoint` | `blocked` | Named blocker with owner or unblocking condition |
| `checkpoint` | `done` | All acceptance criteria have named evidence |
| `blocked` | `work` | Blocker resolved; resolution documented |

## Feature Status Vocabulary

Use these five values for feature/acceptance-criterion status in any storage mode (issue labels or checkboxes, `docs/features.json`, or labeled lines in `docs/project-state.md`):

- `not_started` — identified, no work begun
- `in_progress` — actively being worked on
- `blocked` — specific named condition prevents progress (not "unclear" or "needs thought")
- `passed` — named evidence exists: test, check, commit, or inspected behavior
- `dropped` — explicitly abandoned; record the reason in Dead Ends

A feature moves to `passed` only with named evidence, not a completion claim. A feature moves to `blocked` only with a specific condition.

## Storage Ladder

State storage is chosen by context, in this order:

1. **GitHub issue (preferred).** Use when all three hold:
   - `gh` CLI is installed and authenticated
   - The repo has a GitHub remote (origin matches `github.com`)
   - The "find active issue" algorithm resolves to exactly one issue

   The issue body holds current state; issue comments hold the append-only log.
2. **Repo docs (fallback).** Use when any of the above fails, or when docs are themselves the project deliverable. Canonical file: `docs/project-state.md`. Optional structured ledger: `docs/features.json`.
3. **Branch-local scratch files (autonomous only).** Allowed only in autonomous/unattended mode — no interactive user is present to answer questions (e.g. scheduled runs, loop-style automation, batch agents). Scratch state rides inside the next implementation PR — never drives doc-only PRs.

If the active issue can't be resolved unambiguously by the algorithm below, surface the ambiguity and ask before working.

## Session Startup Sequence

Run these in order. Do not write code until the sequence completes.

1. Resolve the active issue (algorithm below) — or confirm fallback to repo docs.
2. Run `./agent-bootstrap` if it exists.
3. Read the issue body and the most recent handoff comment. In docs mode, read `docs/project-state.md` and `docs/features.json` if present.
4. Read `git log` since the last checkpoint commit.
5. Run the smoke test (fastest meaningful build/test/lint). If no smoke command applies — fresh repo, no build target yet — record "smoke: N/A" explicitly and proceed. **Do not start work on a broken baseline** — fix it or surface it as a blocker first.
6. State the active goal, current position, and any drift in one short message.
7. Surface unapproved drift before writing a line of code.

## First Run

If startup finds no prior state — no issue body, no checkpoint comment, no `docs/project-state.md` — initialize the chosen storage mode before entering `work`:

- **Issue mode:** open an issue using the Issue body template (Goal / Constraints / Acceptance criteria / Dead Ends / Next Actions). Confirm title and goal with the user. In autonomous mode, halt and write `.handoff/halt.md` instead — do not open an issue without human confirmation of the goal.
- **Docs mode:** create `docs/project-state.md` from the template with Goal / Constraints filled in.
- **Scratch mode (autonomous only):** create `.handoff/project-state.md` from the docs-mode template.

Do not skip initialization and rely on chat alone for goal and constraints — that defeats handoff at the first session boundary.

## Finding the Active Issue

On session start, resolve the active issue in this order:

1. Branch name contains `#N` or a known mapping pattern (e.g. `codex/feature-name` resolved via an agent marker file).
2. Recent `git log` contains `relates to #N` or `closes #N`.
3. An agent marker file (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`, or equivalent) explicitly names an active issue. Mere existence of the file does not count.
4. None of the above: surface the ambiguity and ask.

Do not pick an issue by guess or recency.

**In autonomous mode (no user present)**, step 4 has no one to ask — so it instead halts the session: write `.handoff/halt.md` describing what was tried and what's missing, do not write code, and exit. The next interactive session resolves the ambiguity.

## Handoff Comment Template

Use this schema for every checkpoint or handoff comment on the active issue. A fixed schema lets the next session find current state without rereading the thread.

```
**Checkpoint** YYYY-MM-DD

**Branch:** `branch-name`
**What changed:** [1–2 sentences]
**Validation:** [commands run + pass/fail]
**Next action:** [exact next step]
**Blockers/drift:** none
```

When blocked, replace the `Blockers/drift` line with a structured block so the next session doesn't re-run the same failing checks:

```
**Blocker:** [short name]
- Cause: [specific diagnostic — what fails and how, with commands or error excerpts]
- Unblocks when: [named condition or external event]
- Tried: [approaches attempted; link Dead Ends entries if any]
- Skip on resume: [smoke tests or steps the next session should not re-run until cause changes]
```

Do not free-form handoff comments.

## Dead Ends

Track approaches that were tried and abandoned so future sessions don't re-attempt them. Append-only.

- Issue mode: a `Dead Ends:` section in the issue body.
- Docs mode: a `## Dead Ends` section in `docs/project-state.md`.

Format:

```
- YYYY-MM-DD: [approach] — [why it doesn't work]
```

## Accumulators vs. Current State

These are structurally different and must not be mixed in one location.

**Accumulators (append-only, survive across sessions):**

- Done / merged features
- Decisions
- Dead ends
- Validation results

**Current state (replaced each session):**

- Active branch
- In-progress item
- Blockers

Decisions, dead ends, and validation results are all accumulators — they live wherever the accumulator lives for the current storage mode (issue comments, an append-only `docs/decisions.log`, or branch-local notes). Do not edit accumulator entries in place; append a new entry that supersedes the old one.

In issue mode: the issue body holds current state (edited in place); issue comments hold the accumulator. In docs mode: `docs/project-state.md` holds current state; an append-only `docs/decisions.log` (or labeled sections) holds the accumulator.

## Rules

**Test ratchet.** Never remove or weaken tests to make a check pass. If a test is genuinely wrong, fix the test logic and record the change in the decisions log — do not delete it.

**Mandatory startup smoke test.** Do not write code in a session that starts with a failing build or failing smoke test. Fix the baseline first, or surface it as a blocker.

**Separate judge from worker.** For complex or subjective features, define done criteria *before* implementation, then evaluate against them in a separate pass — not by the same agent that wrote the code.

**`passed` requires named evidence.** A test, check, commit, or inspected behavior. Not a completion claim.

**Append-only decisions log.** Plan changes are recorded, not edited in place.

**Redact secrets before writing.** Strip API keys, tokens, passwords, customer PII, and internal URLs from checkpoint bodies, error excerpts, and Dead Ends entries before posting. Especially important in issue mode, where comments are typically public and indexable — a token pasted into a stack trace is a real leak.

**Link, don't restate.** PRDs, ADRs, design docs, prior issues, commits, and diffs already exist — reference them by path, SHA, or URL in checkpoints. Restated content rots: the next session reads the stale copy instead of the source.

## Drift Check

Before substantial implementation, check:

- Does the current task still match the goal and constraints?
- Have prior decisions been bypassed or contradicted?
- Has scope expanded?
- Are temporary deviations documented as temporary?
- Does the next step still serve the active goal?

Classify drift as: approved deviation, unapproved drift, or unknown (needs user confirmation).

## Migrating From Older Repos

Some repos still carry a v1 `docs/project-state.md` or `docs/features.json` from before the skill moved to issue-first storage. If issue mode is available and a v1 doc exists:

1. Copy the active goal, constraints, decisions, and dead ends into the active issue body (current state) and opening comment (accumulator).
2. Verify nothing was lost — read both side by side once.
3. Ask the user whether the old docs can be removed now that state is captured in the issue. Do not delete unilaterally.
4. Until the user approves cleanup, keep reading the old docs as historical context but stop writing to them.

If issue mode is not available, keep using docs mode against the existing files.

For the reverse case — a repo that loses GitHub access mid-project — snapshot the active issue body and recent checkpoint comments into a new `docs/project-state.md` and continue in docs mode.

## Templates

### Issue body (preferred)

```
## Goal
...

## Constraints / Non-goals
- ...

## Acceptance criteria
- [ ] ...

## Dead Ends
- (append-only)

## Next Actions
1. ...
```

### `docs/project-state.md` (fallback, trimmed)

```md
# Project State

## Goal / Constraints
...

## Dead Ends
- (append-only)

## Next Actions
1. ...
```

In docs mode, append decisions to `docs/decisions.log` (preferred) or to a labeled `## Decisions` section in `project-state.md` — pick one and use it consistently. Drift and validation history follow the same accumulator location.

### `docs/features.json` (optional, fallback only)

Only when GitHub is unavailable AND there are multiple trackable outcomes that need objective `pass/block/drop` status. With issues available, this duplicates issue labels — skip it.

```json
{
  "version": 1,
  "project": "project-name",
  "updated_at": "YYYY-MM-DD",
  "active_goal": "current goal",
  "features": [
    {
      "id": "short-stable-id",
      "title": "User-visible or acceptance outcome",
      "status": "not_started",
      "priority": "must",
      "evidence": "",
      "notes": ""
    }
  ]
}
```

For the `status` vocabulary, see "Feature Status Vocabulary" above.

## Optional Repo Scripts

Keep these idempotent, non-destructive, and fast enough for frequent use.

### `./agent-bootstrap`

Purpose: orient a fresh session and confirm the baseline is trustworthy before new work starts.

```sh
#!/usr/bin/env bash
set -euo pipefail

echo "== repo =="
git branch --show-current
git status --short

echo "== active issue =="
# Resolve the active issue from branch name / git log / AGENTS.md, then:
#   gh issue view "$N" --comments | sed -n '1,200p'
# Fall back to docs/project-state.md if no issue.

echo "== smoke =="
# Add the repo's fastest useful build/test/lint check here.
```

### `./agent-check`

Purpose: verify work before updating handoff state.

```sh
#!/usr/bin/env bash
set -euo pipefail

# Add the repo's expected pre-handoff checks here.
```

## Publication Rules

Handoff state is memory, not a deliverable.

- Do not open PRs solely to update `docs/project-state.md`, `docs/decisions.log`, `docs/features.json`, `./agent-bootstrap`, or `./agent-check` unless the user explicitly asks.
- Include docs-mode state-file updates in the same implementation PR as the code they describe.
- If there's no implementation PR yet, leave docs-mode updates local on the branch for the next session.
- In issue mode, write checkpoint comments freely — they are not PRs.
- In scratch mode (autonomous), store state files under `.handoff/` at the repo root. Include them in the next implementation PR or delete them on cleanup; do not commit them to a branch that will never produce a PR, and never open a doc-only PR for them.
- Use a doc-only PR only for an intentional milestone, migration, or repo-wide planning update.

## Response Pattern

When the skill is active:

- Begin by reporting the resolved state: which storage (issue vs docs), active goal, current position, drift.
- Mention drift explicitly if present, before doing any work.
- Keep chat updates concise and factual; prefer issue comments or repo artifacts over long chat recaps.
- End every checkpoint with: validation run, state-store updates made, next 1–3 actions.
