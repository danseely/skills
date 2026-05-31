#!/usr/bin/env bash
# Render markdown to /tmp/render.html and open it in the browser.
#
# Primary path: POST to GitHub's /markdown API (same renderer as github.com,
# returns just the rendered HTML for the markdown body), then embed that HTML
# into a clean template that sets data-color-mode so GitHub's CSS variables
# resolve correctly.
#
# Fallback path: render client-side with marked.js. Used only when the API
# call fails (offline, rate-limited, etc).
#
# Usage: render.sh <input.md>
#        cat foo.md | render.sh -

set -uo pipefail

INPUT="${1:-/tmp/render.md}"
OUT="/tmp/render.html"
ERR="/tmp/render-api.err"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SKILL_DIR/template.html"

[[ -f "$TEMPLATE" ]] || { echo "render.sh: missing template at $TEMPLATE" >&2; exit 2; }

# Read markdown source into a variable.
if [[ "$INPUT" == "-" ]]; then
  MARKDOWN="$(cat)"
elif [[ -f "$INPUT" ]]; then
  MARKDOWN="$(cat "$INPUT")"
else
  echo "render.sh: input file not found: $INPUT" >&2
  exit 2
fi

try_github_api() {
  command -v curl >/dev/null 2>&1 || return 127
  command -v python3 >/dev/null 2>&1 || return 127

  local auth_header=()
  if command -v gh >/dev/null 2>&1; then
    local tok
    tok="$(gh auth token 2>/dev/null)" || tok=""
    if [[ -n "$tok" ]]; then
      auth_header=(-H "Authorization: Bearer $tok")
    fi
  fi

  local payload
  payload="$(MARKDOWN="$MARKDOWN" python3 -c '
import json, os
print(json.dumps({"text": os.environ["MARKDOWN"], "mode": "gfm"}))
')" || return 1

  local html
  html="$(curl -sf --max-time 15 -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "${auth_header[@]}" \
    "https://api.github.com/markdown" \
    --data-binary "$payload" 2>"$ERR")" || return 1

  [[ -n "$html" ]] || return 1

  TEMPLATE_PATH="$TEMPLATE" HTML="$html" OUT_PATH="$OUT" python3 - <<'PY'
import os, json
tpl = open(os.environ['TEMPLATE_PATH']).read()
# Server-rendered: drop CONTENT in, signal "no client fallback needed".
out = tpl.replace('{{CONTENT}}', os.environ['HTML']) \
         .replace('{{MARKDOWN_JSON}}', 'null')
open(os.environ['OUT_PATH'], 'w').write(out)
PY
}

fallback_marked() {
  command -v python3 >/dev/null 2>&1 || { echo "render.sh: need python3 for fallback" >&2; return 2; }
  TEMPLATE_PATH="$TEMPLATE" MARKDOWN="$MARKDOWN" OUT_PATH="$OUT" python3 - <<'PY'
import os, json
tpl = open(os.environ['TEMPLATE_PATH']).read()
md = os.environ['MARKDOWN']
# Client-rendered: leave article empty, pass markdown as JSON string for JS.
out = tpl.replace('{{CONTENT}}', '') \
         .replace('{{MARKDOWN_JSON}}', json.dumps(md))
open(os.environ['OUT_PATH'], 'w').write(out)
PY
}

if try_github_api; then
  : # OK
else
  if [[ -s "$ERR" ]]; then
    echo "render.sh: GitHub /markdown API failed, falling back to marked.js" >&2
    sed 's/^/  /' "$ERR" >&2
  fi
  fallback_marked || exit $?
fi

# Hand off to the system default opener (so browser-routers like OpenIn
# can apply their rules). Set MD_BROWSER to bypass and pin to a
# specific app, e.g. export MD_BROWSER="Arc"
if [[ -n "${MD_BROWSER:-}" ]]; then
  if open -a "$MD_BROWSER" "$OUT" 2>/dev/null; then
    exit 0
  fi
  echo "render.sh: '$MD_BROWSER' not found, falling back to default opener" >&2
fi
open "$OUT"
