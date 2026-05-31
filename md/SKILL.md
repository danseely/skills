---
name: md
description: Render markdown in browser with GitHub styling. Use when producing substantial formatted output that benefits from rendered display - tables, multi-section reports, comparison summaries, documentation, or any response where terminal rendering is inadequate. Trigger phrases include "render this", "show in browser", "open as markdown", or when output contains complex tables/formatting.
---

# Markdown Browser Renderer

Render markdown as a styled HTML page in the user's browser, using GitHub's actual rendering pipeline. Calls GitHub's `/markdown` API directly and wraps the response in a template that loads `github-markdown-css` + `github-syntax-{light,dark}` and sets `data-color-mode` so GitHub's CSS variables resolve.

## Instructions

1. Write the markdown to `/tmp/render.md` (or any path you control).
2. Run `assets/render.sh <path-to-md>` — it handles rendering and opens the result.

That's it. The script writes `/tmp/render.html` and runs `open` on it.

### Piping stdin

```
echo "# hi" | assets/render.sh -
```

## How it works

- **Primary**: `POST https://api.github.com/markdown` with `mode=gfm`, authenticated via `gh auth token` when available (5000/hr vs 60/hr anonymous). The response is rendered HTML — including GFM tables, task lists, and `pl-*` syntax highlight tokens. The script embeds that HTML in `assets/template.html`, which sets `data-color-mode="auto"` on `<html>` and loads:
  - `github-markdown-css` — body, headings, tables, code blocks, blockquotes
  - `github-syntax-light` / `github-syntax-dark` — colors for `pl-*` highlight tokens (light/dark via `prefers-color-scheme`)
- **Fallback**: if the API call fails (offline, rate-limited, no `curl`), the same template is reused with the article left empty; a small inline script loads `marked.js` and renders client-side with GFM enabled.

Either way, output is `/tmp/render.html` — ephemeral, overwritten on next use, no servers left running.

## Notes

- Use only for substantial output where rendering adds value — short replies stay inline.
- The primary path is the genuine GitHub renderer (same parser as github.com, including tables, task lists, syntax highlighting, emoji).
- The fallback is an approximation but works offline.

### Choosing a browser

By default the script just runs `open <file>` and lets the system default opener (or a browser-router like OpenIn) handle routing. To pin a specific app and bypass any router, set:

```
export MD_BROWSER="Arc"          # or "Google Chrome", "Safari", etc.
```

If the named app isn't found, the script falls back to plain `open`.
