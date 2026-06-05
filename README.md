# skills

A small collection of agent skills I use day-to-day. Harness-agnostic: each skill is just a folder with a `SKILL.md` (and optional assets), portable across any agent runtime that supports the SKILL convention — Claude Code, Codex, Cursor, etc.

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
| [`update-mac-app`](./update-mac-app) | Update an unsigned/ad-hoc-signed macOS app to its latest GitHub release — version-check, download the DMG/ZIP, swap the install (old copy to Trash, never deleted), strip Gatekeeper quarantine, relaunch. Targets the current repo's app by default, or any `owner/name` you name. |

## Installing

How you install depends on your agent harness:

- **Claude Code:** drop the skill folder into `~/.claude/skills/<name>/` (user-scope) or `<project>/.claude/skills/<name>/` (project-scope).
- **Codex / others:** consult your runtime's docs for the skills directory.

A common pattern is to clone this repo and symlink individual skills into the runtime's skills directory, so updates from `git pull` propagate.

```sh
git clone https://github.com/danseely/skills.git ~/src/skills
ln -s ~/src/skills/md ~/.claude/skills/md
ln -s ~/src/skills/handoff ~/.claude/skills/handoff
```

## License

[MIT](./LICENSE)
