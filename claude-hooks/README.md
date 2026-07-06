# claude-hooks

Claude Code hook bundles. **Not skills, not harness-agnostic.** Each subdirectory is a self-contained bundle of one or more [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks) plus a README describing what it does and how to install it. They depend on Claude Code's hook events and `settings.json` wiring, so they don't port to other runtimes as-is.

## Bundles

| Bundle | What it does |
|---|---|
| [`tone-hook`](./tone-hook) | Enforces a no-sycophancy, evidence-grounded response style — a `UserPromptSubmit` injection that states the rules each turn, plus a silent, non-blocking `Stop` logger that records banned-phrase hits for tuning. |

## Installing

Each bundle installs by copying (or symlinking) its scripts somewhere stable under `~/.claude/` and registering the hooks in `~/.claude/settings.json`. See the bundle's own README for the exact steps — installs are additive and preserve any hooks you already have.
