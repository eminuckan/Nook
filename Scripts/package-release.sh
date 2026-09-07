#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/package-release.sh --version VERSION [--output-dir DIRECTORY]

Builds Nook and creates a versioned app bundle, zip archive, DMG, and SHA-256
checksums. The script is intended to run on macOS.

Set CODESIGN_IDENTITY to a Developer ID Application identity for a distributable
build. Set NOTARIZE=1 and provide either NOTARYTOOL_KEYCHAIN_PROFILE or the
APPLE_API_KEY_PATH, APPLE_API_KEY_ID, and APPLE_API_ISSUER_ID variables to
notarize and staple the app and DMG.
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

SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARIZE_VALUE="${NOTARIZE:-0}"
NOTARYTOOL_KEYCHAIN_PROFILE="${NOTARYTOOL_KEYCHAIN_PROFILE:-}"
APPLE_API_KEY_PATH="${APPLE_API_KEY_PATH:-}"
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_ID="${APPLE_API_ISSUER_ID:-}"

case "$NOTARIZE_VALUE" in
    1|true|TRUE|yes|YES)
        SHOULD_NOTARIZE=1
        ;;
    0|false|FALSE|no|NO|"")
        SHOULD_NOTARIZE=0
        ;;
    *)
        echo "NOTARIZE must be 0/1 or true/false: $NOTARIZE_VALUE" >&2
        exit 2
        ;;
esac

if [[ "$SHOULD_NOTARIZE" -eq 1 ]]; then
    command -v xcrun >/dev/null 2>&1 || {
        echo "xcrun is required for notarization; install Xcode Command Line Tools." >&2
        exit 1
    }
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        echo "NOTARIZE=1 requires a Developer ID Application CODESIGN_IDENTITY." >&2
        exit 2
    fi
    if [[ -n "$NOTARYTOOL_KEYCHAIN_PROFILE" ]]; then
        :
    elif [[ -z "$APPLE_API_KEY_PATH" || -z "$APPLE_API_KEY_ID" || -z "$APPLE_API_ISSUER_ID" ]]; then
        echo "Notarization requires NOTARYTOOL_KEYCHAIN_PROFILE or APPLE_API_KEY_PATH, APPLE_API_KEY_ID, and APPLE_API_ISSUER_ID." >&2
        exit 2
    elif [[ ! -f "$APPLE_API_KEY_PATH" ]]; then
        echo "App Store Connect API key file does not exist: $APPLE_API_KEY_PATH" >&2
        exit 2
    fi
fi

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
NOTARY_ZIP_PATH="$OUTPUT_DIR/.Nook-$VERSION-$ARCH-notary.zip"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_PATH"
rm -f "$ZIP_PATH" "$DMG_PATH" "$ZIP_PATH.sha256" "$DMG_PATH.sha256" "$NOTARY_ZIP_PATH"

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

# An ad-hoc signature keeps local builds usable without an Apple Developer
# certificate. Distributable builds should provide a Developer ID identity;
# those builds use the hardened runtime and a secure timestamp.
CODESIGN_ARGS=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    CODESIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${CODESIGN_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

notarize() {
    local artifact="$1"

    echo "Submitting $(basename "$artifact") for notarization"
    if [[ -n "$NOTARYTOOL_KEYCHAIN_PROFILE" ]]; then
        xcrun notarytool submit "$artifact" \
            --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE" \
            --wait \
            --no-progress
    else
        xcrun notarytool submit "$artifact" \
            --key "$APPLE_API_KEY_PATH" \
            --key-id "$APPLE_API_KEY_ID" \
            --issuer "$APPLE_API_ISSUER_ID" \
            --wait \
            --no-progress
    fi
}

if [[ "$SHOULD_NOTARIZE" -eq 1 ]]; then
    # Notarize a zip of the app first so the stapled ticket is included in the
    # final zip as well as in the DMG.
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"
    notarize "$NOTARY_ZIP_PATH"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    rm -f "$NOTARY_ZIP_PATH"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create \
    -volname "Nook $VERSION" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
    codesign --verify --strict "$DMG_PATH"
fi

if [[ "$SHOULD_NOTARIZE" -eq 1 ]]; then
    notarize "$DMG_PATH"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --verbose=4 "$DMG_PATH"
fi

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "Created:"
printf '  %s\n' "$APP_PATH" "$ZIP_PATH" "$DMG_PATH" "$ZIP_PATH.sha256" "$DMG_PATH.sha256"
