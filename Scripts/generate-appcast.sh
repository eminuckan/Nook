#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: Scripts/generate-appcast.sh STABLE_VERSION RELEASE_DIRECTORY" >&2
    exit 2
fi
VERSION="$1"
OUTPUT_DIR="$(cd "$2" && pwd)"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
ARCHIVE="$OUTPUT_DIR/Nook-$VERSION-$(uname -m).zip"
[[ -f "$ARCHIVE" ]] || { echo "Missing release ZIP: $ARCHIVE" >&2; exit 1; }

# A fresh directory guarantees one full update, no stale assets or delta links.
FEED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nook-appcast.XXXXXX")"
trap 'rm -rf "$FEED_DIR"' EXIT
cp "$ARCHIVE" "$FEED_DIR/"
SIGNING_ARGS=(--account com.nook.quicknotes)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    SIGNING_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
"$SPARKLE_BIN/generate_appcast" "${SIGNING_ARGS[@]}" \
    --download-url-prefix "https://github.com/eminuckan/Nook/releases/download/v$VERSION/" \
    --maximum-deltas 0 "$FEED_DIR"
"$SPARKLE_BIN/sign_update" "${SIGNING_ARGS[@]}" --verify "$FEED_DIR/appcast.xml"
swift "$ROOT_DIR/Scripts/verify-appcast.swift" "$FEED_DIR/appcast.xml" "$ARCHIVE" \
    "$ROOT_DIR/Resources/Info.plist" "$VERSION"
cp "$FEED_DIR/appcast.xml" "$OUTPUT_DIR/appcast.xml"
echo "Created signed appcast: $OUTPUT_DIR/appcast.xml"
