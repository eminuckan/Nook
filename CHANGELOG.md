# Changelog

This file records user-facing changes. Versions follow [Semantic Versioning](https://semver.org/).

## [0.2.2] - 2026-09-08

- Remove the empty standalone Settings window that could appear when opening Nook.
- The macOS Settings menu and Command-comma open the real settings inside the Nook panel.
- Preserve native editing and quit shortcuts with an explicit application menu.

## [0.2.1] - 2026-09-08

- Packaged apps resolve icons from their own resources instead of requiring the build machine’s SwiftPM directory.
- Opening an already-running Nook from Spotlight or Finder reveals its panel.

## [0.2.0] - 2026-09-08

- Default tags are English: Inbox, Ideas, Design, Tasks, and Personal. Existing tags marked as old built-ins migrate without changing custom labels or note content.
- Signed GitHub update checks with manual Install and Relaunch, an automatic-check setting, and a menu-bar Check for Updates action.
- Launch at login can be enabled or disabled in Settings, with macOS approval and error states shown accurately.
- Native drafts that cannot be serialized block navigation and prompt before quitting or updating.

- A new vector folded-corner mark stays legible in the menu bar and adapts to its appearance; release bundles include the matching macOS app icon.
- Photos and file attachments persist inside notes, including their display size; existing RTF notes remain readable.
- Photos have space above and below, and typing after a photo keeps the surrounding body style.
- Editor formatting preserves embedded content and table cells, supports undo/redo and cursor formatting, and continues lists on Return.
- The editor has direct formatting controls, visible save feedback, and a word count. Attachment pickers keep the editing panel open.
- Save errors can be retried, unreadable note files are protected, and quitting warns about unsaved changes.
- Release packaging supports optional Developer ID signing, hardened runtime, Apple notarization, and stapled tickets. The default release path remains ad-hoc for local use.

## [0.1.0] - 2026-09-08

The first public release of Nook.

- Quick notes from the macOS menu bar.
- Local note storage with search, tags, pinning, filters, and manual ordering.
- Rich text editing with lists, native tables, pasted images, photos, and file attachments.
- Light/Dark/System appearance, language selection, Spaces behavior, and an editable global shortcut.
- A movable panel that snaps to a safe edge of the active display.
