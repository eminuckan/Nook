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

## Build and run

```sh
swift build -c release
./.build/release/Nook
```

Nook is a menu-bar app, so launching it does not open a regular document window. Look for the note icon in the menu bar. Right-click that icon to quit.

## Data and privacy

Notes are stored in:

```text
~/Library/Application Support/Nook/notes.json
```

Appearance, language, shortcut, and custom-tag preferences are kept in the standard macOS `UserDefaults` store for the app. The source does not send note content anywhere.

## Contributing

Issues and pull requests are welcome. Before opening a pull request, please run a release build and describe any UI or behavior changes in the PR. Keep changes small and preserve the local-first behavior.

## License

Nook is released under the MIT License. See [LICENSE](LICENSE).
