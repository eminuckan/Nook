# Nook

Nook is a small notes app that lives in the macOS menu bar. It opens a quiet panel at the edge of the screen, so writing something down takes one click and does not require leaving the app you are using.

This started as a personal tool. It is intentionally focused: quick notes, a few useful tags, and an editor that stays out of the way. It is not meant to replace Apple Notes or become a full document-management system.

## What it does

- Opens from the menu bar or with the global `⌘⌥N` shortcut (the shortcut can be changed in Settings).
- Keeps notes locally on the Mac; there is no account, sync service, telemetry, or network dependency.
- Supports titles, rich text, lists, native editable tables, inline photos, file attachments, and pasted images.
- Includes tags, pinning, manual drag-and-drop ordering, search, and Today/Pinned filters.
- Follows the system appearance by default, with Light and Dark overrides.
- Can stay visible across Spaces. The panel itself can be moved between displays and snaps back to a nearby screen edge when released.
- Uses the menu-bar icon’s secondary click for a complete “Quit Nook” action.

## Requirements

- macOS 13 Ventura or newer
- Swift 5.9 or newer

Nook uses AppKit and SwiftUI from the system SDK. There are no third-party package dependencies.

## Install a release

Download the latest `.dmg` from [GitHub Releases](https://github.com/eminuckan/Nook/releases), open it, and drag Nook to Applications. The current public asset (`v0.1.0`) is for Apple Silicon (`arm64`) and is ad-hoc signed for local use, so macOS can show a Gatekeeper warning. For your own Mac, right-click Nook and choose **Open** the first time.

## Build and run from source

```sh
swift build -c release
./.build/release/Nook
```

Nook is a menu-bar app, so launching it does not open a regular document window. Look for the note icon in the menu bar. Right-click that icon to quit.

To create local release assets (`.app`, `.zip`, `.dmg`, and checksums):

```sh
./Scripts/package-release.sh --version 0.1.0
```

The packaging script is macOS-only because it uses `codesign`, `ditto`, and `hdiutil`.

## Releases and versioning

Nook uses [Semantic Versioning](https://semver.org/). Every tag in the form `vMAJOR.MINOR.PATCH` starts the release workflow in [`.github/workflows/release.yml`](.github/workflows/release.yml). GitHub Actions builds the app, creates the DMG and zip archives, writes SHA-256 checksums, and publishes them to a GitHub Release.

To publish the next release:

```sh
git switch main
git pull --ff-only
git tag -a v0.1.1 -m "Release v0.1.1"
git push origin v0.1.1
```

Update [`CHANGELOG.md`](CHANGELOG.md) before tagging. The release workflow generates the GitHub notes from the commits and attaches the build files automatically.

### Maintainer release setup

The current release job publishes ad-hoc assets for local use. When Nook is ready for wider distribution, switch the release job to notarization and configure these repository secrets in GitHub:

- `APPLE_CERTIFICATE_P12_BASE64` — base64 of a **Developer ID Application** certificate export.
- `APPLE_CERTIFICATE_PASSWORD` — password used for that `.p12` export.
- `APPLE_API_KEY_BASE64` — base64 of an App Store Connect API key (`.p8`).
- `APPLE_API_KEY_ID` and `APPLE_API_ISSUER_ID` — the matching API key identifiers.

The notarized workflow imports the certificate into a temporary keychain, enables the hardened runtime, submits the app and DMG to Apple’s notary service, and staples the resulting tickets. Keep the original certificate and API key files out of the repository. The Apple Developer Program membership is required for these credentials.

For a local signed build, set `CODESIGN_IDENTITY` to the installed Developer ID identity. Add `NOTARIZE=1` and the same API-key variables when you also want to notarize locally; without those variables the script remains useful for local ad-hoc builds only.

## Data and privacy

Notes are stored in:

```text
~/Library/Application Support/Nook/notes.json
```

Appearance, language, shortcut, and custom-tag preferences are kept in the standard macOS `UserDefaults` store for the app. The source does not send note content anywhere.

## Contributing

Issues and pull requests are welcome. The short version is in [`CONTRIBUTING.md`](CONTRIBUTING.md): keep changes focused, run the release build and `git diff --check`, and describe UI changes with a screenshot when useful.

## License

Nook is released under the MIT License. See [`LICENSE`](LICENSE).
