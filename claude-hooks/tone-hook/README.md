# claude-hook: response discipline

**Not a skill, and not harness-agnostic.** These are two [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks) that enforce a no-sycophancy, evidence-grounded response style. They rely on Claude Code's `UserPromptSubmit` and `Stop` hook events and its `settings.json` wiring, so they do not port to other runtimes as-is.

## What it does

- **`user-prompt-submit.sh`** — injects a fixed response-discipline ruleset as `additionalContext` at the start of every turn (maximally recent, so most reliably followed). No sycophancy, no provisional agreement, no hedge/confidence words without evidence, disagreement when the user is wrong, brevity. Silent: it never blocks and produces no visible output.
- **`stop.sh`** — a silent, non-blocking violation logger. When a turn ends it greps the assistant's text for banned hedge/sycophancy phrases and appends any hits to `~/.claude/logs/tone-violations.log`. It never emits a `decision: block`, so it produces zero in-session chatter and never forces a redo. It's a tuning signal, not a gate.

Prevention (the injection) does the work; detection (the logger) tells you how well it's working so you can tune the ruleset.

### Why hooks and not a skill

A skill is loaded when the model chooses to invoke it. This behavior has to apply to *every* turn and be checked *after* generation — neither is something a skill can do. Only hooks fire deterministically on those events.

## Install

Copy the folder somewhere stable (or symlink it) and register the two hooks in `~/.claude/settings.json`:

```sh
mkdir -p ~/.claude/tone-hooks
cp claude-hooks/tone-hook/*.sh ~/.claude/tone-hooks/
chmod +x ~/.claude/tone-hooks/*.sh
```

Then register them, preserving any existing hooks/statusline (idempotent — re-running replaces prior entries for these scripts):

```sh
S="$HOME/.claude/settings.json"
UP="$HOME/.claude/tone-hooks/user-prompt-submit.sh"
ST="$HOME/.claude/tone-hooks/stop.sh"
cp "$S" "$S.bak"
jq --arg up "$UP" --arg st "$ST" '
  .hooks = (.hooks // {}) |
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
    | map(select([.hooks[]?.command // ""] | any(contains("/tone-hooks/")) | not))) +
    [{matcher: "", hooks: [{type: "command", command: $up, timeout: 5}]}] |
  .hooks.Stop = ((.hooks.Stop // [])
    | map(select([.hooks[]?.command // ""] | any(contains("/tone-hooks/")) | not))) +
    [{matcher: "", hooks: [{type: "command", command: $st, timeout: 30}]}]
' "$S" > "$S.tmp" && jq empty "$S.tmp" && mv "$S.tmp" "$S"
```

Hooks are read at session start, so this takes effect in a **new** session, not mid-session.

## Toggle off

Both scripts short-circuit if a sentinel file exists:

```sh
touch ~/.claude/tone-hooks/OFF   # disable
rm   ~/.claude/tone-hooks/OFF    # re-enable
```

## Tuning the logger

The banned-phrase list in `stop.sh` is coarse and will produce false positives (`likely`, `could be`, `might be` in legitimate use). It's a signal, not a blocker. Prune the `PATTERNS` list against real hits in `~/.claude/logs/tone-violations.log`.
