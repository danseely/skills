---
name: update-mac-app
description: Update an unsigned/ad-hoc-signed macOS app to its latest version — resolve where the app gets updates (a GitHub release, or a Sparkle appcast feed discovered from the installed bundle), download the newest DMG/ZIP, replace the install (old copy to Trash, never deleted), strip Gatekeeper quarantine, and relaunch. Works whether or not you have the source repo locally: name the app, pass an owner/name repo, or run it inside the app's repo. Trigger phrases include "update agendum", "update <app>", "is my <app> up to date", "pull the latest <app>", "upgrade <app>", "update this app", "update an app I have installed".
version: 3.0.0
---

# Update an unsigned macOS app

Updates a locally installed macOS app to its newest version. Built for apps that
are **unsigned or ad-hoc-signed** and distributed **outside** the App Store (so
they need the Gatekeeper-quarantine handling a notarized app wouldn't).

The core idea: an update **source** yields two things — the latest **version**
and a direct **download URL** to a `.dmg` or `.zip`. Two source kinds are
supported, and once resolved the install steps are identical:

- **GitHub release** — when you name an `owner/name` repo, or run inside the
  app's repo. Latest version + asset come from `gh release`.
- **Sparkle appcast** — for an app you just have installed, with no repo. The
  app's own `Contents/Info.plist` usually points at its update feed
  (`SUFeedURL`); that feed's newest `<enclosure>` is the download URL, hosted
  wherever the vendor keeps it. GitHub is not required.

This means you can update an app you have **no local connection to** — just one
you have installed — as long as it advertises a Sparkle feed (most third-party
Mac apps with a "Check for Updates…" menu item do).

## Step 0 — Identify the app and resolve its update source

End this step with **either** a GitHub repo (`REPO`) **or** an appcast feed URL
(`FEED`), plus the installed bundle path (`DEST`) whenever you can determine it.
Resolve in this order:

1. **Explicit GitHub repo argument** (`owner/name`) → set `REPO`. Skip to Step 1.

2. **A named/installed app** ("update Foo", "update this app I have"). Locate the
   installed bundle, then read its update feed:

   ```bash
   NAME="Foo"   # what the user called it, with or without .app
   DEST=$(mdfind "kMDItemContentType == 'com.apple.application-bundle' && kMDItemFSName == '${NAME%.app}.app'" 2>/dev/null | head -1)
   [ -z "$DEST" ] && DEST=$(/bin/ls -d "/Applications/${NAME%.app}.app" "$HOME/Applications/${NAME%.app}.app" 2>/dev/null | head -1)
   echo "installed bundle: ${DEST:-<not found>}"
   FEED=$(plutil -extract SUFeedURL raw "$DEST/Contents/Info.plist" 2>/dev/null || echo "")
   echo "appcast feed: ${FEED:-<none in Info.plist>}"
   ```

   - If `FEED` is set → appcast source. Continue to Step 1.
   - If the bundle has no `SUFeedURL`, it has no Sparkle feed to follow. Fall
     through to options 3/4 (maybe its repo is the cwd, otherwise ask the user
     for an `owner/name`).
   - If multiple bundles match the name, show them and ask which.

3. **No argument** → assume the app built by the current directory's repo:

   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
   echo "repo from cwd: ${REPO:-<none>}"
   ```

4. **Fall back to asking.** If nothing above resolves a source, ask the user for
   the app name or `owner/name`. Do not guess a repo from the app's name —
   updating from the wrong source is worse than asking.

**Confirm the resolved source with the user before downloading** — especially an
auto-discovered appcast feed. Show what you found (e.g. "Foo updates from
`https://vendor.example/appcast.xml`") so they can veto a wrong/untrusted feed.

> Trust note: this skill downloads straight from the source's URL and does **not**
> verify Sparkle's EdDSA update signature. That is consistent with these apps
> already being unsigned, but it does mean the feed URL is trusted as-is. Only
> proceed with feeds the user recognizes.

## Step 1 — Get the latest version and download URL

**GitHub source:**

```bash
gh release view --repo "$REPO" --json tagName,assets \
  --jq '{tag: .tagName, assets: [.assets[].name]}'
```

- `AVAIL` = tag with any leading `v` stripped. Choose the `.dmg` (preferred) or
  `.zip` asset into `ASSET`; for per-arch builds pick the one matching `uname -m`
  or ask. No mac asset → this repo has no mac update path; fall back to Step 0.4.

**Appcast source:** parse the feed for the newest item's version and enclosure
URL. The feed is RSS with Sparkle namespaced fields; parse it properly rather
than grepping:

```bash
read AVAIL URL < <(python3 - "$FEED" <<'PY'
import sys, urllib.request, xml.etree.ElementTree as ET
SP = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ns = {'sparkle': SP}
data = urllib.request.urlopen(sys.argv[1], timeout=20).read()
root = ET.fromstring(data)
best = None
for it in root.findall('.//item'):
    if it.find('sparkle:channel', ns) is not None:   # skip beta/non-default channels
        continue
    enc = it.find('enclosure')
    if enc is None or not enc.get('url'):
        continue
    short = it.findtext('sparkle:shortVersionString', '', ns) or enc.get('{%s}shortVersionString' % SP) or ''
    build = it.findtext('sparkle:version', '', ns) or enc.get('{%s}version' % SP) or ''
    try: bnum = int(build)
    except ValueError: bnum = -1
    key = (bnum, [int(x) for x in short.split('.') if x.isdigit()])
    if best is None or key > best[0]:
        best = (key, short or build, enc.get('url'))
if not best:
    sys.exit('no usable enclosure in appcast')
print(best[1], best[2])
PY
)
ASSET=$(basename "${URL%%\?*}")   # filename, query stripped
echo "latest: $AVAIL  url: $URL"
```

If the enclosure is a `.pkg` or `.tar.*` rather than `.dmg`/`.zip`, stop and tell
the user — this skill swaps an `.app` bundle and does not run package installers.

## Step 2 — Compare against the install (short-circuit if current)

If you already know `DEST` (appcast path, or a named app you located), compare
before downloading:

```bash
INSTALLED=$(plutil -extract CFBundleShortVersionString raw "$DEST/Contents/Info.plist" 2>/dev/null || echo "none")
echo "installed: $INSTALLED  available: $AVAIL"
```

- `INSTALLED` == `AVAIL` → **already current, stop.** Report nothing changed.
- `INSTALLED` == `none` (or `DEST` unknown, as with a fresh GitHub lookup) →
  proceed; the install path is confirmed after download in Step 4.
- Otherwise it's behind. If unsure which is newer, newest is the last line of
  `printf '%s\n' "$INSTALLED" "$AVAIL" | sort -V`.

Tell the user installed-vs-available before changing anything.

## Step 3 — Download the asset

Fresh scratch dir under `$TMPDIR` (never under `$HOME`):

```bash
WORK=$(mktemp -d "${TMPDIR:-/tmp}/update-mac-app.XXXXXX")
```

```bash
# GitHub source:
gh release download "v${AVAIL#v}" --repo "$REPO" --pattern "$ASSET" --dir "$WORK" --clobber 2>/dev/null \
  || gh release download "$AVAIL" --repo "$REPO" --pattern "$ASSET" --dir "$WORK" --clobber

# Appcast source:
curl -fL --retry 2 "$URL" -o "$WORK/$ASSET"
```

## Step 4 — Open the asset and read the candidate bundle

End with `APP_SRC` (the `.app` in the download) and `BUNDLE` (its filename).

**DMG:**

```bash
DMG="$WORK/$ASSET"
ATTACH=$(yes | hdiutil attach -nobrowse "$DMG")           # `yes |` auto-accepts any license prompt
MOUNT=$(printf '%s\n' "$ATTACH" | grep -o '/Volumes/.*' | tail -1)   # last column = mount point, may contain spaces
APP_SRC=$(/bin/ls -d "$MOUNT"/*.app 2>/dev/null | head -1)
BUNDLE=$(basename "$APP_SRC")
```

**ZIP:**

```bash
ZIP="$WORK/$ASSET"
ditto -x -k "$ZIP" "$WORK/extracted"
APP_SRC=$(find "$WORK/extracted" -maxdepth 3 -name '*.app' | head -1)
BUNDLE=$(basename "$APP_SRC")
```

Confirm the install path and the candidate version:

```bash
NEWVER=$(plutil -extract CFBundleShortVersionString raw "$APP_SRC/Contents/Info.plist")
DEST="${DEST:-/Applications/$BUNDLE}"
[ -d "$DEST" ] || DEST="/Applications/$BUNDLE"
[ -d "$DEST" ] || DEST="$HOME/Applications/$BUNDLE"
echo "candidate: $NEWVER  installing to: $DEST"
```

If `DEST` already exists and its version equals `NEWVER`, you were current after
all — detach/clean up (Step 8) and report no change.

## Step 5 — Quit the app if running

Replacing a running bundle is unsafe. Process name is the bundle minus `.app`:

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

The app is unsigned/unnotarized. A CLI download usually does **not** set
`com.apple.quarantine`, so no "developer cannot be verified" dance is needed.
Check anyway, and strip it if present so the app launches directly:

```bash
if xattr -r "$DEST" 2>/dev/null | grep -qi quarantine; then
  xattr -dr com.apple.quarantine "$DEST"
  echo "stripped quarantine"
else
  echo "no quarantine attribute — no privacy dance needed"
fi
```

If macOS still refuses to launch (rare for ad-hoc-signed local installs), tell
the user to open **System Settings > Privacy & Security**, click **Open Anyway**
on the blocked-app notice, then `open` the app again.

## Step 8 — Launch, confirm, and clean up

```bash
open "$DEST"
sleep 4
pgrep -lf "${BUNDLE%.app}"
plutil -extract CFBundleShortVersionString raw "$DEST/Contents/Info.plist"

[ -n "${MOUNT:-}" ] && hdiutil detach "$MOUNT" -quiet || true
rm -rf "$WORK"
```

`rm -rf "$WORK"` is safe here: `$WORK` is the `mktemp -d` path from Step 3 and
used nowhere else. Use that exact variable — never a retyped literal.

## Reporting

Tell the user the before/after versions, the source you updated from (repo or
feed URL), that the app relaunched, and where the old version went (Trash,
recoverable). If already on the latest, say so and that nothing changed. If old
copies are piling up in the Trash, mention they may want to empty it.

## Notes / gotchas

- **Source priority:** explicit repo → named/installed app's appcast → cwd repo →
  ask. Never auto-pick a repo from an app's name.
- **Only stable channel:** the appcast parser skips items tagged with a
  `<sparkle:channel>` (betas). If the user wants a pre-release, remove that
  filter or ask.
- **Only `.dmg`/`.zip` enclosures.** `.pkg`/`.tar.*` need a different install
  path (package installer, often `sudo`) and are out of scope — bail and say so.
- The mount-point parse takes the last whitespace-delimited column of `hdiutil
  attach` output, so volume names with spaces (`/Volumes/Agendum Neo v0.5.4`)
  work without guessing the volume name.
- `/Applications` and `~/.Trash` are normally writable without `sudo`. If `cp`
  into `/Applications` is denied, fall back to `~/Applications` or ask.
- For apps with a built-in Sparkle updater UI, that updater is the vendor's
  intended path; this skill just does the same fetch from the CLI.
