# Nook

Nook is a small notes app that lives in the macOS menu bar. It opens a quiet panel at the edge of the screen, so writing something down takes one click and does not require leaving the app you are using.

This started as a personal tool. It is intentionally focused: quick notes, a few useful tags, and an editor that stays out of the way. It is not meant to replace Apple Notes or become a full document-management system.

## What it does

- Opens from the menu bar or with the global `⌘⌥N` shortcut (the shortcut can be changed in Settings).
- Keeps notes locally on the Mac; there is no account, note sync service, or telemetry.
- Supports titles, rich text, lists, native editable tables, inline photos, file attachments, and pasted images.
- Keeps photos and files inside the saved note, with undo/redo for editing actions, inline formatting at the cursor, and list continuation on Return.
- Includes tags, pinning, manual drag-and-drop ordering, search, and Today/Pinned filters.
- Follows the system appearance by default, with Light and Dark overrides.
- Can stay visible across Spaces. The panel itself can be moved between displays and snaps back to a nearby screen edge when released.
- Checks for new GitHub releases automatically, with a setting to disable scheduled checks. Updates are installed only when you choose Install and Relaunch.
- Offers Check for Updates and Quit Nook from the menu-bar icon’s secondary click.
- Can launch at login, controlled in Settings and reflected from macOS Login Items.

## Requirements

- macOS 13 Ventura or newer
- Swift 5.9 or newer

Nook uses AppKit and SwiftUI from the system SDK, and Sparkle for signed app updates.

## Install a release

Download the latest `.dmg` from [GitHub Releases](https://github.com/eminuckan/Nook/releases), open it, and drag Nook to Applications. The release is for Apple Silicon (`arm64`) and is ad-hoc signed, not Developer ID signed or Apple notarized. macOS can therefore block the first launch. After verifying the source, use the app-specific **Open Anyway** option in System Settings → Privacy & Security where macOS offers it. Do not disable Gatekeeper globally. See [Apple’s explanation of the different security warnings](https://support.apple.com/en-gb/102445).

In Nook Settings, **Automatically check for updates** controls scheduled GitHub checks, and **Launch at login** controls macOS startup registration. Right-click the menu-bar icon and choose **Check for Updates…** for an immediate check. Sparkle verifies each update with Nook’s Ed25519 public key; this protects the update channel but does not replace Apple notarization. The app saves notes before installing and relaunching. See [update publishing and signing](docs/UPDATES.md).

## Build and run from source

```sh
swift build -c release
./.build/release/Nook
```

Nook is a menu-bar app, so launching it does not open a regular document window. Look for the note icon in the menu bar. Right-click that icon to quit.

Run `swift test` for document round trips, native editing, and persistence recovery checks. For an isolated UI session, run `./.build/debug/Nook --preview`; preview notes use the temporary `Nook-Editor-Preview` directory instead of your personal notes folder.

To create local release assets (`.app`, `.zip`, `.dmg`, and checksums):

```sh
./Scripts/package-release.sh --version 0.1.0
```

The packaging script is macOS-only because it uses `codesign`, `ditto`, and `hdiutil`.

The icon masters are editable SVGs in `Sources/Nook/Resources`: `NookLogo.svg` for the monochrome menu-bar mark and `NookAppIcon.svg` for the app icon. After editing the app icon, run `swift Scripts/render-app-icon.swift` to regenerate the bundled `Resources/Nook.icns` and 1024-pixel PNG.

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

Appearance, language, shortcut, custom-tag, and update-check preferences are kept in the standard macOS `UserDefaults` store for the app. Launch-at-login state is managed by macOS. Update checks connect to GitHub to retrieve release metadata and update packages; note content is never sent.

Rich note bodies use self-contained RTFD data in the existing `bodyRTF` JSON field; legacy RTF notes remain readable. Save failures are shown with a retry action. If an existing notes file cannot be read, Nook preserves it and blocks writes until the file is repaired or moved safely aside.

## Contributing

Issues and pull requests are welcome. The short version is in [`CONTRIBUTING.md`](CONTRIBUTING.md): keep changes focused, run the release build and `git diff --check`, and describe UI changes with a screenshot when useful.

## License

Nook is released under the MIT License. See [`LICENSE`](LICENSE).
