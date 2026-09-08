<p align="center">
  <img src="Resources/NookIcon.png" alt="Nook app icon" width="112" height="112">
</p>

<h1 align="center">Nook</h1>

<p align="center">
  <strong>A small place for your thoughts. Right beside your work.</strong><br>
  A native macOS menu-bar notes app with a floating panel and local storage.
</p>

<p align="center">
  <a href="https://github.com/eminuckan/Nook/releases/latest"><img src="https://img.shields.io/github/v/release/eminuckan/Nook?style=flat&amp;color=dea04e" alt="Latest release"></a>
  <a href="https://github.com/eminuckan/Nook/actions/workflows/ci.yml"><img src="https://github.com/eminuckan/Nook/actions/workflows/ci.yml/badge.svg" alt="Build status"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-555555?style=flat" alt="Requires macOS 13 or newer">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555?style=flat" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://github.com/eminuckan/Nook/releases/latest"><strong>Download for Mac</strong></a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">What's new</a>
  &nbsp;·&nbsp;
  <a href="ROADMAP.md">Roadmap</a>
  &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">Contribute</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/eminuckan/Nook/issues">Report an issue</a>
</p>

---

## Keep a thought within reach

Open Nook from the menu bar or press **⌘⌥N**, jot something down, and keep the note beside the app you're working in. The panel stays above normal windows until you hide it. Move it to another display, let it snap to a nearby edge, or keep it across Spaces.

Nook started as a personal tool for quick notes. No account to create, no workspace to set up—just a place to write, organize, and return to later.

| Write | Find | Make it yours |
| :--- | :--- | :--- |
| Rich text, lists, and editable tables | Tags, search, and Today/Pinned filters | System, Light, and Dark appearance |
| Inline photos, pasted images, and file attachments | Pinned notes and manual drag-and-drop ordering | Custom global shortcut and language selection |
| Undo/redo and visible save feedback | A floating panel that stays within reach | Launch at login and optional visibility across Spaces |

## A quick tour

1. **Launch Nook** to open the panel automatically at the right edge. Reopen it from the menu-bar icon or **⌘⌥N**. The shortcut is configurable in Settings.
2. **Capture** a note with a title, formatted text, or an attachment.
3. **Organize** with a tag or pin; use search when you need it again.
4. **Keep it nearby** while working in another app. Use the panel's minimize control or menu-bar icon to hide it.

## Get Nook

Download the latest `.dmg` from [GitHub Releases](https://github.com/eminuckan/Nook/releases/latest), open it, and drag Nook to Applications. The release is for Apple Silicon (`arm64`) and is ad-hoc signed, not Developer ID signed or Apple notarized. macOS can therefore block the first launch. After verifying the source, use the app-specific **Open Anyway** option in System Settings → Privacy & Security where macOS offers it. Do not disable Gatekeeper globally. See [Apple’s explanation of the different security warnings](https://support.apple.com/en-gb/102445).

In Nook Settings, **Automatically check for updates** controls scheduled GitHub checks, and **Launch at login** controls macOS startup registration. Right-click the menu-bar icon and choose **Check for Updates…** for an immediate check. Sparkle verifies each update with Nook’s Ed25519 public key; this protects the update channel but does not replace Apple notarization. The app saves notes before installing and relaunching. See [update publishing and signing](docs/UPDATES.md).

## Data and privacy

Notes are stored in:

```text
~/Library/Application Support/Nook/notes.json
```

Appearance, language, shortcut, custom-tag, and update-check preferences are kept in the standard macOS `UserDefaults` store for the app. Launch-at-login state is managed by macOS. Update checks connect to GitHub to retrieve release metadata and update packages; note content is never sent.

Rich note bodies use self-contained RTFD data in the existing `bodyRTF` JSON field; legacy RTF notes remain readable. Save failures are shown with a retry action. If an existing notes file cannot be read, Nook preserves it and blocks writes until the file is repaired or moved safely aside.

## What's next

The [roadmap](ROADMAP.md) sets out the planned order: reliability and portable notes, Windows and Linux, optional sync, mobile apps, audio recording, voice-to-text, and drawing tools. Optional AI with your own API key is an exploration. These are future plans; the current release is a local macOS app.

## Development

Requires macOS and Swift 5.9 or newer. Nook uses SwiftUI, AppKit, and Sparkle.

```sh
git clone https://github.com/eminuckan/Nook.git
cd Nook
swift build -c release
./.build/release/Nook
```

Nook is a menu-bar app that opens its floating notes panel automatically on launch. Use the note icon in the menu bar to hide or reopen the panel. Right-click that icon to quit.

Run `swift test` for document round trips, native editing, and persistence recovery checks. The tests require full Xcode; if Command Line Tools is selected, use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`. For an isolated UI session, run `./.build/debug/Nook --preview`; preview notes use the temporary `Nook-Editor-Preview` directory instead of your personal notes folder.

<details>
<summary><strong>Packaging and icon assets</strong></summary>

To create local release assets (`.app`, `.zip`, `.dmg`, and checksums):

```sh
./Scripts/package-release.sh --version 0.2.6
```

The packaging script is macOS-only because it uses `codesign`, `ditto`, and `hdiutil`.

The icon masters are editable SVGs in `Sources/Nook/Resources`: `NookLogo.svg` for the monochrome menu-bar mark and `NookAppIcon.svg` for the app icon. After editing the app icon, run `swift Scripts/render-app-icon.swift` to regenerate the bundled `Resources/Nook.icns` and 1024-pixel PNG.


</details>

<details>
<summary><strong>Releases and signing</strong></summary>

Nook follows [Semantic Versioning](https://semver.org/). Changes go through pull requests with passing checks before merging to `main`. Update [`CHANGELOG.md`](CHANGELOG.md), then tag the merged commit with the next unused `vMAJOR.MINOR.PATCH` version.

The [release workflow](.github/workflows/release.yml) tests the app, builds the DMG and ZIP, creates SHA-256 checksums, and signs and verifies the Sparkle update feed before publishing. Write user-facing release notes describing the changes and any verification limits.

Current releases use ad-hoc signing. The packaging script also supports local Developer ID signing and optional notarization: set `CODESIGN_IDENTITY`, and use `NOTARIZE=1` with the credentials described by `./Scripts/package-release.sh --help`. The GitHub workflow does not currently enable Apple notarization.

See [update publishing and signing](docs/UPDATES.md) for Sparkle key setup and release verification. Keep private keys and certificates out of the repository.

</details>

## Contributing

Bug reports, focused pull requests, and small improvements are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and required checks, or [open an issue](https://github.com/eminuckan/Nook/issues) to describe a problem.

## License

[MIT](LICENSE) · Made by [Emin Uçkan](https://github.com/eminuckan).
