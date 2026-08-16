#!/bin/bash
#
# One-time setup: generates the EdDSA key pair Patchly's own updates are
# signed with. The private key is stored in your login Keychain by
# Sparkle's own `generate_keys` tool — this script never sees or handles
# it directly. Run this once, then paste the printed public key into
# Patchly/Info.plist's SUPublicEDKey value.
#
#   scripts/generate-sparkle-keys.sh
#
# scripts/release.sh's `sign_update` step reads the same Keychain entry
# to sign each release's DMG.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/scripts/.sparkle-tools"
BIN_DIR="$TOOLS_DIR/bin"

step() { printf '\n\033[1;33m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

if [[ ! -x "$BIN_DIR/generate_keys" ]]; then
  step "Downloading Sparkle's CLI tools"
  command -v curl >/dev/null || fail "curl not found"
  TAG="$(curl -fsSL https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$TAG" ]] || fail "could not determine the latest Sparkle release tag"
  URL="https://github.com/sparkle-project/Sparkle/releases/download/$TAG/Sparkle-$TAG.tar.xz"
  mkdir -p "$TOOLS_DIR"
  ARCHIVE="$TOOLS_DIR/Sparkle-$TAG.tar.xz"
  curl -fsSL "$URL" -o "$ARCHIVE" || fail "download failed: $URL"
  tar -xf "$ARCHIVE" -C "$TOOLS_DIR" bin/generate_keys bin/sign_update
  rm -f "$ARCHIVE"
  chmod +x "$BIN_DIR"/generate_keys "$BIN_DIR"/sign_update
  echo "  tools installed to $BIN_DIR ($TAG)"
fi

step "Checking for an existing signing key"
if "$BIN_DIR/generate_keys" -p 2>/dev/null; then
  echo
  echo "A Sparkle signing key already exists in your Keychain (public key printed above)."
  echo "Paste it into Patchly/Info.plist's SUPublicEDKey value."
  exit 0
fi

step "Generating a new EdDSA key pair"
echo "macOS may prompt for Keychain access below — allow it."
echo
"$BIN_DIR/generate_keys"

echo
echo "Paste the public key printed above into Patchly/Info.plist's SUPublicEDKey value."
