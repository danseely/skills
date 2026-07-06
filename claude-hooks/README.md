# claude-hooks

Claude Code hook plugins. **Not skills, not harness-agnostic.** Each subdirectory is a self-contained plugin (a `.claude-plugin/plugin.json` manifest plus a `hooks/hooks.json` and its scripts) that ships one or more [Claude Code hooks](https://code.claude.com/docs/en/hooks). They depend on Claude Code's hook events, so they don't port to other runtimes as-is.

## Plugins

| Plugin | What it does |
|---|---|
| [`tone-hook`](./tone-hook) | Enforces a no-sycophancy, evidence-grounded response style — a `UserPromptSubmit` injection that states the rules each turn, plus a silent, non-blocking `Stop` logger that records banned-phrase hits for tuning. |

## Installing

These are published through the `skills` marketplace at the repo root. Add it once, then install any plugin by name:

```
/plugin marketplace add danseely/skills
/plugin install tone-hook@skills
```

See each plugin's own README for what it does and any per-plugin toggles.
