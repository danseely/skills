---
name: update-mac-app
description: Update an unsigned/ad-hoc-signed macOS app to the latest GitHub release — compare the installed version against the newest release, and if behind, download the DMG/ZIP asset, replace the install (old copy to Trash, never deleted), strip Gatekeeper quarantine, and relaunch. Works for any app shipped as a `.dmg` or `.zip` release asset from a GitHub repo. With no argument, it targets the app built by the current session's repo. Trigger phrases include "update agendum", "update <app>", "is my <app> up to date", "pull the latest <app>", "upgrade <app>", "update this app", "update the mac app for this repo".
version: 2.0.0
---

# Update an unsigned macOS app

Updates a locally installed macOS app to the latest GitHub release. Built for
apps that are **unsigned or ad-hoc-signed** and shipped as a `.dmg` or `.zip`
release asset (so they need the Gatekeeper-quarantine handling that a notarized
App Store / Sparkle app wouldn't).

Everything is derived dynamically — the GitHub repo, the release tag, the asset,
the `.app` bundle name, and the installed path. There is no per-app config file.

## Step 0 — Resolve the target repo

Figure out which GitHub repo ships the app, in this priority order:

1. **Explicit argument.** If the user named a repo (`owner/name`) or a repo
   path, use it. If they named only an app ("update Foo") with no repo you
   recognize, ask for the `owner/name`.
2. **Current session directory.** If no argument was given, assume the app is
   the one built by the repo of the current working directory:

   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
   echo "repo from cwd: ${REPO:-<none>}"
   ```

3. **Fall back to asking.** If the cwd is not a git repo, or (per Step 1) that
   repo has no mac-app release asset, ask the user which app/repo to update.
   Do not guess.

State which repo you resolved before continuing.

## Step 1 — Find the latest release and its mac asset

```bash
gh release view --repo "$REPO" --json tagName,assets \
  --jq '{tag: .tagName, assets: [.assets[].name]}'
```

- `tag` is the release tag (e.g. `v0.5.4` or `0.5.4`).
- Pick the mac asset from `assets`: prefer a single `.dmg`; otherwise a single
  `.zip`. If there are several candidates (e.g. per-arch builds), pick the one
  matching this machine's arch (`uname -m` → `arm64` / `x86_64`, often spelled
  `arm64`/`aarch64` vs `x64`/`intel` in filenames) or ask the user which.
- **If there is no `.dmg`/`.zip` asset**, this repo has no mac-app update path.
  Say so and fall back to Step 0.3 (ask which app to update). The asset may also
  just not be built yet — check
  `gh run list --workflow release.yml --repo "$REPO"` before assuming failure.

Set `TAG` to the tag and `ASSET` to the chosen filename.

## Step 2 — Download the asset

Use a fresh scratch dir under `$TMPDIR` (never under `$HOME`):

```bash
WORK=$(mktemp -d "${TMPDIR:-/tmp}/update-mac-app.XXXXXX")
gh release download "$TAG" --repo "$REPO" --pattern "$ASSET" --dir "$WORK" --clobber
```

## Step 3 — Open the asset and read the candidate bundle

Branch on the asset type. In both cases you end with `APP_SRC` (path to the
`.app` in the download) and `BUNDLE` (its `.app` filename).

**DMG:**

```bash
DMG="$WORK/$ASSET"
# `yes |` auto-accepts any license agreement (SLA) prompt.
ATTACH=$(yes | hdiutil attach -nobrowse "$DMG")
MOUNT=$(printf '%s\n' "$ATTACH" | grep -o '/Volumes/.*' | tail -1)   # last column = mount point, may contain spaces
APP_SRC=$(/bin/ls -d "$MOUNT"/*.app 2>/dev/null | head -1)
BUNDLE=$(basename "$APP_SRC")
echo "mounted at: $MOUNT  bundle: $BUNDLE"
```

**ZIP:**

```bash
ZIP="$WORK/$ASSET"
ditto -x -k "$ZIP" "$WORK/extracted"
APP_SRC=$(find "$WORK/extracted" -maxdepth 3 -name '*.app' | head -1)
BUNDLE=$(basename "$APP_SRC")
echo "extracted bundle: $BUNDLE"
```

Read the candidate's version (prefer `plutil` — it reads any path reliably):

```bash
NEWVER=$(plutil -extract CFBundleShortVersionString raw "$APP_SRC/Contents/Info.plist")
echo "candidate version: $NEWVER"
```

## Step 4 — Compare against the install and decide

The installed path is derived from the bundle name:

```bash
DEST="/Applications/$BUNDLE"
[ -d "$DEST" ] || DEST="$HOME/Applications/$BUNDLE"   # fall back to per-user Applications
INSTALLED=$(plutil -extract CFBundleShortVersionString raw "$DEST/Contents/Info.plist" 2>/dev/null || echo "none")
echo "installed: $INSTALLED  latest: $NEWVER (tag $TAG)"
```

- If `INSTALLED` equals `NEWVER`: **already on the latest — stop.** Detach/clean
  up (Step 8) and report that nothing changed.
- If `INSTALLED` is `none`: no existing install — proceed to install fresh into
  `/Applications/$BUNDLE`.
- Otherwise it's behind — proceed. If unsure which is newer, the newest is the
  last line of `printf '%s\n' "$INSTALLED" "$NEWVER" | sort -V`.

> Optimization: if you can confidently identify the installed bundle before
> downloading (the user named the app and it exists in `/Applications`), you may
> compare its version to `TAG` first (strip a leading `v` from the tag) and skip
> Steps 2–3 entirely when already current. When in doubt, download and compare
> real bundle versions — correctness over saving one download.

Tell the user what you found (installed vs latest) before changing anything.

## Step 5 — Quit the app if running

Replacing a running bundle is unsafe. The process name is the bundle name
without `.app`:

```bash
PROC="${BUNDLE%.app}"
if pgrep -f "$PROC" >/dev/null; then
  osascript -e "quit app \"$PROC\"" 2>/dev/null || true
  sleep 2
  pgrep -f "$DEST" >/dev/null && pkill -f "$DEST" || true
  sleep 1
fi
```

## Step 6 — Replace the install (old copy to Trash — never `rm -rf`)

Do **not** delete the old app. Move it to the Trash with a version + timestamp
suffix so it never collides with an existing Trash entry and stays recoverable.

```bash
set -e
if [ -d "$DEST" ]; then
  OLDVER=$(plutil -extract CFBundleShortVersionString raw "$DEST/Contents/Info.plist" 2>/dev/null || echo "unknown")
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$DEST" "$HOME/.Trash/${BUNDLE%.app} ($OLDVER $ts).app"
fi
cp -R "$APP_SRC" "$DEST"
plutil -extract CFBundleShortVersionString raw "$DEST/Contents/Info.plist"
```

## Step 7 — Strip Gatekeeper quarantine if present

The app is unsigned/unnotarized. A CLI download via `gh` + `cp` usually does
**not** set `com.apple.quarantine`, so no "developer cannot be verified" dance
is needed. Check anyway, and strip it if present so the app launches directly:

```bash
if xattr -r "$DEST" 2>/dev/null | grep -qi quarantine; then
  xattr -dr com.apple.quarantine "$DEST"
  echo "stripped quarantine"
else
  echo "no quarantine attribute — no privacy dance needed"
fi
```

If macOS still refuses to launch (rare for ad-hoc-signed local installs), tell
the user to open **System Settings > Privacy & Security**, scroll to the
blocked-app notice, click **Open Anyway**, then `open` the app again.

## Step 8 — Launch, confirm, and clean up

```bash
open "$DEST"
sleep 4
pgrep -lf "${BUNDLE%.app}"
plutil -extract CFBundleShortVersionString raw "$DEST/Contents/Info.plist"

# Clean up: detach the DMG (if mounted) and remove the scratch dir.
[ -n "${MOUNT:-}" ] && hdiutil detach "$MOUNT" -quiet || true
rm -rf "$WORK"
```

`rm -rf "$WORK"` is safe here: `$WORK` is the `mktemp -d` path created in Step 2
and used nowhere else. Use that exact variable — never a retyped literal.

## Reporting

Tell the user the before/after versions, that the app relaunched, and where the
old version went (Trash, recoverable). If they were already on the latest, say
so and that nothing was changed. If old copies are piling up in the Trash from
repeated updates, mention they may want to empty it.

## Notes / gotchas

- These commands run as the logged-in user; `/Applications` and `~/.Trash` are
  normally writable without `sudo`. If `cp` into `/Applications` is denied, the
  app may have been installed system-wide — fall back to `~/Applications` or ask.
- The mount-point parse in Step 3 takes the last whitespace-delimited column of
  `hdiutil attach` output, so volume names with spaces (e.g.
  `/Volumes/Agendum Neo v0.5.4`) work without guessing the volume name.
- Some DMGs wrap the `.app` in a subfolder or include an `Applications` symlink;
  `ls "$MOUNT"/*.app` targets the real bundle. For ZIPs the `find` covers a
  nested layout.
- This skill is for apps distributed **outside** the App Store / without a
  built-in updater (Sparkle, etc.). If the app self-updates, prefer that.
