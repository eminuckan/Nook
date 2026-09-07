#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/package-release.sh --version VERSION [--output-dir DIRECTORY]

Builds Nook and creates a versioned app bundle, zip archive, DMG, and SHA-256
checksums. The script is intended to run on macOS.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
OUTPUT_DIR="$ROOT_DIR/dist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; usage >&2; exit 2; }
            VERSION="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || { echo "Missing value for --output-dir" >&2; usage >&2; exit 2; }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "A version is required." >&2
    usage >&2
    exit 2
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Version must use SemVer, for example 0.1.0 or 0.1.0-rc.1: $VERSION" >&2
    exit 2
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

command -v hdiutil >/dev/null 2>&1 || {
    echo "hdiutil is required; run this script on macOS." >&2
    exit 1
}

BUILD_NUMBER="${NOOK_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '1')"
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Build number must be numeric: $BUILD_NUMBER" >&2
    exit 2
fi

ARCH="$(uname -m)"
APP_PATH="$OUTPUT_DIR/Nook.app"
ZIP_PATH="$OUTPUT_DIR/Nook-$VERSION-$ARCH.zip"
DMG_PATH="$OUTPUT_DIR/Nook-$VERSION-$ARCH.dmg"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_PATH"
rm -f "$ZIP_PATH" "$DMG_PATH" "$ZIP_PATH.sha256" "$DMG_PATH.sha256"

echo "Building Nook $VERSION for $ARCH"
swift build -c release --package-path "$ROOT_DIR"

BINARY_PATH="$ROOT_DIR/.build/release/Nook"
if [[ ! -x "$BINARY_PATH" ]]; then
    echo "Build completed without an executable at $BINARY_PATH" >&2
    exit 1
fi

mkdir -p "$APP_PATH/Contents/MacOS"
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/Nook"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PATH/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

# An ad-hoc signature makes the locally built bundle launchable while keeping
# the script usable without an Apple Developer certificate. CI can provide a
# real identity through CODESIGN_IDENTITY when one is available.
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create \
    -volname "Nook $VERSION" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "Created:"
printf '  %s\n' "$APP_PATH" "$ZIP_PATH" "$DMG_PATH" "$ZIP_PATH.sha256" "$DMG_PATH.sha256"
