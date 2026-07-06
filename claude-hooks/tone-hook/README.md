# tone-hook

**A Claude Code plugin, not a skill, and not harness-agnostic.** It enforces a no-sycophancy, evidence-grounded response style through two [Claude Code hooks](https://code.claude.com/docs/en/hooks). It depends on Claude Code's `UserPromptSubmit` and `Stop` hook events, so it does not port to other runtimes as-is.

## What it does

- **`user-prompt-submit.sh`** — injects a fixed response-discipline ruleset as `additionalContext` at the start of every turn (maximally recent, so most reliably followed). No sycophancy, no provisional agreement, no hedge/confidence words without evidence, disagreement when the user is wrong, brevity. Silent: it never blocks and produces no visible output.
- **`stop.sh`** — a silent, non-blocking violation logger. When a turn ends it scans the assistant's final message (via the `last_assistant_message` hook field, falling back to the transcript) for banned hedge/sycophancy phrases and appends any hits to `~/.claude/logs/tone-violations.log`. It never emits a `decision: block`, so it produces zero in-session chatter and never forces a redo. It's a tuning signal, not a gate.

Prevention (the injection) does the work; detection (the logger) tells you how well it's working so you can tune the ruleset.

### Why hooks and not a skill

A skill is loaded when the model chooses to invoke it. This behavior has to apply to *every* turn and be checked *after* generation — neither is something a skill can do. Only hooks fire deterministically on those events.

## Install

This plugin is published through the `skills` marketplace (the repo root). Add the marketplace once, then install:

```
/plugin marketplace add danseely/skills
/plugin install tone-hook@skills
```

Plugin changes apply once the plugin loads — start a **new** session, or run `/reload-plugins` in the current one. Enable, disable, and update through `/plugin`.

## Toggle off (without disabling the plugin)

Both scripts short-circuit if a sentinel file exists — a fast, no-restart mute:

```sh
touch ~/.claude/tone-hook.OFF   # mute
rm   ~/.claude/tone-hook.OFF    # unmute
```

## Tuning the logger

The banned-phrase list in `stop.sh` is coarse and will produce false positives (`likely`, `could be`, `might be` in legitimate use). It's a signal, not a blocker. Prune the `PATTERNS` list against real hits in `~/.claude/logs/tone-violations.log`.

## Layout

```
tone-hook/
  .claude-plugin/plugin.json   # plugin manifest
  hooks/
    hooks.json                 # registers the two hook events
    scripts/
      user-prompt-submit.sh
      stop.sh
```
