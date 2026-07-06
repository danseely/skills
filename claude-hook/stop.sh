#!/usr/bin/env bash
# Stop hook: SILENT violation logger. Never blocks, never spawns anything,
# emits no stdout — zero in-session chatter. Greps the just-finished assistant
# turn for banned hedge/sycophancy phrases and appends hits to a tuning log.
# Toggle off: touch ~/.claude/tone-hooks/OFF
#
# Stdin: JSON with transcript_path, session_id. Stdout: nothing (always exit 0).
set -euo pipefail

[ -f "$HOME/.claude/tone-hooks/OFF" ] && exit 0

VIOL_FILE="$HOME/.claude/logs/tone-violations.log"
mkdir -p "$HOME/.claude/logs"

HOOK_INPUT=$(cat)
SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
TRANSCRIPT=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

[ -f "$TRANSCRIPT" ] || exit 0

# Isolate the assistant text produced since the last REAL user turn
# (user-typed text, not tool_result lines which carry a tool_use_id).
last_user=$(grep -n '"type":"user"' "$TRANSCRIPT" 2>/dev/null | grep -v '"tool_use_id"' | tail -1 | cut -d: -f1 || true)
if [ -n "$last_user" ]; then
  slice=$(tail -n +"$last_user" "$TRANSCRIPT" 2>/dev/null || true)
else
  slice=$(cat "$TRANSCRIPT" 2>/dev/null || true)
fi

assistant_text=$(printf '%s\n' "$slice" \
  | jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
  | tr '\n' ' ' || true)

[ -n "$assistant_text" ] || exit 0

# Coarse tuning signal, not a blocker — expect false positives ("likely",
# "could be" in legitimate use). Prune this list against real hits in the log.
PATTERNS='i think|probably|likely|i believe|fairly certain|should be|i.d guess|i suspect|presumably|in theory|my sense is|if i recall|i assume|seems like|might be|could be|great question|good point|you.re absolutely right|you.re right'

hits=$(printf '%s' "$assistant_text" | grep -ioE "$PATTERNS" 2>/dev/null | sort | uniq -c | sort -rn || true)

if [ -n "$hits" ]; then
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] session=$SESSION"
    printf '%s\n' "$hits" | sed 's/^/  /'
  } >> "$VIOL_FILE"
fi

exit 0
