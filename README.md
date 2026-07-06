# skills

A small collection of agent skills I use day-to-day. Skills are harness-agnostic by default: each is just a folder with a `SKILL.md` (and optional assets), portable across any agent runtime that supports the SKILL convention — Claude Code, Codex, Cursor, etc. **Unless a subdirectory says otherwise** — some folders here are harness-specific (e.g. [`claude-hooks`](./claude-hooks) holds Claude Code hook plugins, not portable skills). Each such folder's own README states its scope.

This repo also doubles as a Claude Code **plugin marketplace** (see [`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json)): `/plugin marketplace add danseely/skills`, then `/plugin install <name>@skills`.

## What's a skill?

A directory containing a `SKILL.md` file with YAML frontmatter (`name`, `description`) and a body the agent loads as instructions when the skill is invoked. Optional sibling files (scripts, templates, references) live alongside.

```
<skill-name>/
  SKILL.md          # frontmatter + agent instructions
  assets/           # optional: scripts, templates, etc.
```

## Skills in this repo

| Skill | What it does |
|---|---|
| [`handoff`](./handoff) | Durable project state across sessions — state machine over GitHub issues (preferred) or repo docs, with checkpoints, drift checks, and a feature-status vocabulary. |
| [`md`](./md) | Render markdown to a styled HTML page in the user's browser, using GitHub's `/markdown` API for the real GFM pipeline (tables, task lists, syntax highlighting). |
| [`transfer`](./transfer) | Drop or pick up a transfer document so a fresh session can continue work — timestamped files in a global `~/.claude/transfers/` store, shared across projects, newest pending wins on pickup. |
| [`update-mac-app`](./update-mac-app) | Update an unsigned/ad-hoc-signed macOS app to its newest version — resolves the update source (a GitHub release, or a Sparkle appcast feed discovered from the installed bundle's `Info.plist`), downloads the DMG/ZIP, swaps the install (old copy to Trash, never deleted), strips Gatekeeper quarantine, relaunches. Works for an app you only have installed, an `owner/name` repo, or the current repo's app. |

## Harness-specific (not skills)

| Folder | What it does |
|---|---|
| [`claude-hooks`](./claude-hooks) | Claude Code hook plugins (not portable skills), one per subdirectory. Currently [`tone-hook`](./claude-hooks/tone-hook): a no-sycophancy, evidence-grounded response style via a `UserPromptSubmit` injection plus a silent `Stop` logger. |

## Installing skills

How you install a skill depends on your agent harness:

- **Claude Code:** drop the skill folder into `~/.claude/skills/<name>/` (user-scope) or `<project>/.claude/skills/<name>/` (project-scope).
- **Codex / others:** consult your runtime's docs for the skills directory.

A common pattern is to clone this repo and symlink individual skills into the runtime's skills directory, so updates from `git pull` propagate.

```sh
git clone https://github.com/danseely/skills.git ~/src/skills
ln -s ~/src/skills/md ~/.claude/skills/md
ln -s ~/src/skills/handoff ~/.claude/skills/handoff
```

## Installing plugins (Claude Code)

The hook plugins under [`claude-hooks`](./claude-hooks) are published through this repo's [`marketplace.json`](./.claude-plugin/marketplace.json). Add the marketplace once, then install any plugin by name:

```
/plugin marketplace add danseely/skills
/plugin install tone-hook@skills
```

Manage them afterward with `/plugin` — enable, disable, or update (`/plugin marketplace update skills` pulls the latest, then `/plugin` to reinstall). Plugin hooks are read at session start, so changes take effect in a new session.

## Migrating from a manual `tone-hook` install

Earlier `tone-hook` was installed by hand: scripts symlinked into `~/.claude/tone-hooks/` and `UserPromptSubmit`/`Stop` entries added to `~/.claude/settings.json`. If you did that, install the plugin (above) **and** remove the manual wiring, or both copies fire and the injection doubles up.

```sh
# 1. Drop the manually-registered hooks (only the ones pointing at /tone-hooks/).
S="$HOME/.claude/settings.json"
cp "$S" "$S.premigrate.bak"
jq '
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
    | map(select([.hooks[]?.command // ""] | any(contains("/tone-hooks/")) | not))) |
  .hooks.Stop = ((.hooks.Stop // [])
    | map(select([.hooks[]?.command // ""] | any(contains("/tone-hooks/")) | not))) |
  # drop the arrays entirely if now empty
  if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end |
  if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
' "$S" > "$S.tmp" && jq empty "$S.tmp" && mv "$S.tmp" "$S"

# 2. Remove the old symlinked scripts.
rm -f ~/.claude/tone-hooks/user-prompt-submit.sh ~/.claude/tone-hooks/stop.sh
rmdir ~/.claude/tone-hooks 2>/dev/null || true   # only if now empty

# 3. Restart Claude Code so the removal and the plugin both take effect.
```

The no-restart mute also moved: use `~/.claude/tone-hook.OFF` (the old path was `~/.claude/tone-hooks/OFF`).

## License

[MIT](./LICENSE)
