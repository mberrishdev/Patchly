#!/bin/bash
#
# Cuts a Patchly release: bumps the version, archives Release, packages a DMG,
# and publishes a GitHub release with the DMG attached.
#
#   scripts/release.sh 0.0.2            # build, tag, and publish
#   scripts/release.sh 0.0.2 --dry-run  # build and package only, publish nothing
#
# Patchly has no Developer ID yet, so the app is ad-hoc signed rather than
# notarized: Gatekeeper will show "unidentified developer" on first launch,
# bypassed with a right-click -> Open. This also EdDSA-signs the DMG with
# scripts/generate-sparkle-keys.sh's Keychain-stored key and prepends a new
# <item> to appcast.xml so Patchly's own Sparkle updater can find the
# release. There is no Homebrew cask yet, so that isn't touched here.

set -euo pipefail

VERSION="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/release.sh <version> [--dry-run]" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must be semver, e.g. 0.0.2 (got '$VERSION')" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TAG="v$VERSION"
BUILD_DIR="$REPO_ROOT/.build/release"
ARCHIVE="$BUILD_DIR/Patchly.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGE_DIR="$BUILD_DIR/dmg"
DMG="$BUILD_DIR/Patchly-$VERSION.dmg"

step() { printf '\n\033[1;33m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

step "Preflight"
command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v hdiutil >/dev/null || fail "hdiutil not found"
SIGN_UPDATE="$REPO_ROOT/scripts/.sparkle-tools/bin/sign_update"
[[ -x "$SIGN_UPDATE" ]] || fail "sign_update not found — run scripts/generate-sparkle-keys.sh first"
if ! $DRY_RUN; then
  command -v gh >/dev/null || fail "gh not found — install the GitHub CLI"
  gh auth status >/dev/null 2>&1 || fail "gh is not authenticated — run 'gh auth login'"
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]] && ! $DRY_RUN; then
  fail "releases are cut from main (on '$CURRENT_BRANCH')"
fi
if [[ -n "$(git status --porcelain)" ]] && ! $DRY_RUN; then
  fail "working tree is dirty — commit or stash first"
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  fail "tag $TAG already exists"
fi
echo "  version $VERSION, tag $TAG, branch $CURRENT_BRANCH"

# ------------------------------------------------------------------- tests

step "Tests"
xcodebuild test \
  -project Patchly.xcodeproj \
  -scheme Patchly \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
echo "  suite passed"

# ------------------------------------------------------------------- build

if $DRY_RUN; then
  step "Skipping the version bump (dry run)"
else
  step "Setting version to $VERSION"
  # project.yml is the source of truth once xcodegen is in the loop — editing
  # project.pbxproj directly would get silently reverted the next time
  # someone runs `xcodegen generate` for an unrelated structural change.
  BUILD_NUMBER="$(git rev-list --count HEAD)"
  command -v xcodegen >/dev/null || fail "xcodegen not found — brew install xcodegen"
  /usr/bin/sed -i '' \
    -e "s/^\([[:space:]]*\)MARKETING_VERSION: .*$/\1MARKETING_VERSION: \"$VERSION\"/" \
    -e "s/^\([[:space:]]*\)CURRENT_PROJECT_VERSION: .*$/\1CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" \
    project.yml
  xcodegen generate --quiet

  # Every configuration must agree, or Debug and Release disagree about what
  # version is running.
  STRAY="$(grep -c "MARKETING_VERSION = $VERSION;" Patchly.xcodeproj/project.pbxproj || true)"
  TOTAL="$(grep -c "MARKETING_VERSION = " Patchly.xcodeproj/project.pbxproj || true)"
  [[ "$STRAY" == "$TOTAL" ]] || fail "only $STRAY of $TOTAL MARKETING_VERSION entries became $VERSION"
  echo "  marketing $VERSION, build $BUILD_NUMBER ($TOTAL configurations)"
fi

step "Archiving Release"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project Patchly.xcodeproj \
  -scheme Patchly \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/Patchly.app"
[[ -d "$APP_IN_ARCHIVE" ]] || fail "archive has no Patchly.app"

mkdir -p "$EXPORT_DIR"
cp -R "$APP_IN_ARCHIVE" "$EXPORT_DIR/Patchly.app"
APP="$EXPORT_DIR/Patchly.app"
echo "  archived $(du -sh "$APP" | cut -f1)"

if ! $DRY_RUN; then
  BUILT_SHORT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist" 2>/dev/null || echo "")"
  BUILT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
    "$APP/Contents/Info.plist" 2>/dev/null || echo "")"
  [[ "$BUILT_SHORT" == "$VERSION" ]] \
    || fail "the built app reports version '$BUILT_SHORT', not $VERSION"
  echo "  reports $BUILT_SHORT ($BUILT_BUILD)"
fi

# Ad-hoc sign if the archive came out unsigned, so Gatekeeper's message is
# "unidentified developer" rather than "damaged". Patchly has no Developer ID
# yet — this is the whole signing story for now.
if ! codesign -dv "$APP" >/dev/null 2>&1; then
  step "Ad-hoc signing (no Developer ID in this build)"
  codesign --force --deep --sign - "$APP"
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority|Signature" | sed 's/^/  /' || true

# --------------------------------------------------------------------- dmg

step "Packaging DMG"
rm -rf "$STAGE_DIR" "$DMG"
mkdir -p "$STAGE_DIR"
cp -R "$APP" "$STAGE_DIR/Patchly.app"
ln -s /Applications "$STAGE_DIR/Applications"
# hdiutil reports "Resource busy" if the freshly copied bundle is still being
# indexed, so give it a few attempts.
for attempt in 1 2 3 4 5; do
  if hdiutil create \
      -volname "Patchly $VERSION" \
      -srcfolder "$STAGE_DIR" \
      -ov -format UDZO \
      "$DMG" >/dev/null 2>&1; then
    break
  fi
  [[ $attempt == 5 ]] && fail "hdiutil could not create the DMG"
  echo "  hdiutil busy, retrying ($attempt)"
  sleep 3
done
hdiutil verify "$DMG" >/dev/null 2>&1 || fail "the DMG failed verification"

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "  $DMG ($(du -h "$DMG" | cut -f1))"
echo "  sha256 $SHA"

step "Signing the update for Sparkle"
SIGNATURE_ATTRS="$("$SIGN_UPDATE" "$DMG")"
echo "  $SIGNATURE_ATTRS"

if $DRY_RUN; then
  step "Dry run — nothing published"
  echo "  DMG: $DMG"
  echo "  version bump not written (dry run) — project.pbxproj is untouched"
  echo "  appcast.xml not updated (dry run)"
  exit 0
fi

step "Adding $VERSION to appcast.xml"
ITEM_FILE="$BUILD_DIR/appcast-item.xml"
PUB_DATE="$(LC_TIME=C date -u +"%a, %d %b %Y %H:%M:%S %z")"
cat > "$ITEM_FILE" <<EOF
    <item>
      <title>Patchly $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <enclosure
        url="https://github.com/mberrishdev/Patchly/releases/download/$TAG/Patchly-$VERSION.dmg"
        type="application/octet-stream"
        $SIGNATURE_ATTRS />
    </item>
EOF
MARKER="<!-- scripts/release.sh inserts new <item> entries directly below this line, newest first -->"
grep -qF "$MARKER" appcast.xml || fail "appcast.xml is missing the release.sh insertion marker"
/usr/bin/sed -i '' "\\@$MARKER@r $ITEM_FILE" appcast.xml
rm -f "$ITEM_FILE"
echo "  prepended the $VERSION entry"

# ----------------------------------------------------------------- publish

step "Committing and tagging"
git add project.yml Patchly.xcodeproj/project.pbxproj appcast.xml
if git diff --cached --quiet; then
  echo "  nothing staged — version already matches"
else
  git commit -q -m "Release $VERSION"
  echo "  committed the version bump"
fi
git tag -a "$TAG" -m "Patchly $VERSION"
git push -q origin main
git push -q origin "$TAG"
echo "  pushed $TAG"

step "Publishing the GitHub release"
NOTES_FILE="$BUILD_DIR/notes.md"
PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
{
  echo "## Install"
  echo
  echo "Download **Patchly-$VERSION.dmg** below, drag Patchly into Applications."
  echo
  echo "This build is ad-hoc signed (no Apple Developer ID yet), so on first"
  echo "launch macOS will say it can't verify the app. Right-click -> Open ->"
  echo "Open again to bypass that — only needed once."
  echo
  echo "## Changes"
  echo
  if [[ -n "$PREV_TAG" ]]; then
    git log --no-merges --pretty='- %s' "$PREV_TAG..$TAG"
  else
    git log --no-merges --pretty='- %s' -20 "$TAG"
  fi
} > "$NOTES_FILE"

gh release create "$TAG" "$DMG" \
  --title "Patchly $VERSION" \
  --notes-file "$NOTES_FILE"

step "Done"
echo "  release: $(gh release view "$TAG" --json url -q .url)"
