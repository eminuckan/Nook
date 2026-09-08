# Nook roadmap

Nook is growing from a macOS notes companion into a place to capture and revisit thoughts across devices. The priorities below are ordered by dependency and usefulness: protect existing notes, make them portable, connect devices, then add more ways to capture and work with them.

This is a direction, not a release schedule. Unchecked items are future work, not features available today. Scope and order may change as we learn from issues, prototypes, and user feedback. Shipped changes belong in the [changelog](CHANGELOG.md).

## Priorities at a glance

| Order | Focus | Status | Why here |
| :--- | :--- | :--- | :--- |
| 1 | Reliability and portable notes | Next | Every new client and capture format depends on preserving existing content. |
| 2 | Optional synchronization | Planned | Make the same notes available across devices without sacrificing offline use. |
| 3 | Mobile apps for iOS and Android | Planned | Bring capture and access to phones on top of the tested sync foundation. |
| 4 | Audio notes | Planned | Save recordings as notes before adding transcription on top. |
| 5 | Voice-to-text notes | Planned | Turn speech into editable text, with a clear choice about retaining the recording. |
| 6 | Drawings and sketches | Planned | Add an editable visual capture format across desktop and mobile. |
| 7 | Optional AI with your own API key | Exploring | Build on reliable capture and storage; validate useful actions before committing to providers. |
| 8 | Windows and Linux apps | Deferred | Revisit desktop expansion after the higher-priority features; other milestones do not depend on these ports. |

## 1. Reliability and portable notes

- [ ] Close remaining focus, clipboard, editing, and save/recovery issues in the macOS app.
- [ ] Define a versioned note format that can be read and written across platforms, including rich text, tables, images, and attachments.
- [ ] Provide safe migration and export/backup paths for existing notes before changing storage.

**Ready to move on when:** representative existing notes survive migration and round trips without losing text, formatting, or attachments, and failed saves remain recoverable. The current macOS RTFD representation needs an explicit compatibility plan before other clients depend on it.

## 2. Optional synchronization

- [ ] Synchronize notes and attachments between devices while keeping offline reading and editing available.
- [ ] Handle concurrent edits, deletions, interrupted transfers, and reconnects without silently losing content.
- [ ] Show sync progress, failures, and recoverable conflicts clearly.
- [ ] Decide and document hosting, identity, encryption, and data-deletion behavior before inviting users to sync personal notes.

**Ready to move on when:** two macOS devices can edit offline, reconnect, and converge with understandable conflict handling and recoverable failures. Validate the shared sync contract on macOS first; Windows and Linux ports are not prerequisites. Sync is optional; local-only use remains available. No hosting provider or account model is selected by this roadmap.

## 3. Mobile apps

- [ ] Bring Nook to iOS and Android for quick capture and access to existing notes.
- [ ] Support offline editing and synchronization with desktop clients.
- [ ] Design touch-friendly editing and capture without assuming desktop window behavior.

**Ready to move on when:** a note can move between a phone and desktop through real offline/reconnect workflows without losing supported content. Mobile prototypes can start earlier, but synced releases depend on the previous milestone.

## 4. Audio notes

- [ ] Record directly into a note and keep the original audio as an attachment.
- [ ] Play recordings back inside Nook and allow users to export them.
- [ ] Handle microphone permission, interrupted recording, storage limits, and attachment transfer safely.

**Ready to move on when:** recordings survive save, reopen, export, and sync. Recording an audio note does not require transcription or AI.

## 5. Voice-to-text notes

- [ ] Convert speech into editable note text.
- [ ] Let users choose between a text note and text with the original recording retained.
- [ ] Evaluate transcription quality, language support, processing location, and cost before selecting an implementation.

**Ready to move on when:** a failed transcription cannot destroy an existing recording or draft, and users understand whether audio stays on-device or is sent to a service. No transcription provider or offline capability is promised yet.

## 6. Drawings and sketches

- [ ] Create and edit drawings inside notes with pointer or touch input.
- [ ] Preserve editable drawing data and provide a viewable representation on other clients.
- [ ] Support saving, reopening, exporting, and synchronizing drawings alongside text and attachments.

**Ready to move on when:** sketches remain editable on supported clients and readable elsewhere. This is a new drawing tool; attaching an existing image is already supported today.

## 7. Optional AI — bring your own key

- [ ] Explore explicit actions such as summarizing a note, rewriting selected text, or extracting tasks.
- [ ] Let users configure their own provider API key (BYOK) and understand provider charges.
- [ ] Store credentials securely and make the content sent to a provider clear before an action runs.
- [ ] Keep AI optional; ordinary note capture, editing, and storage work without a key.

**Decision gate:** validate a small set of useful actions, supported providers, privacy behavior, and failure handling before turning this exploration into a delivery commitment. AI is not a dependency for audio recording, drawings, or synchronization.

## 8. Windows and Linux apps

- [ ] Build Windows and Linux desktop clients with quick capture, local persistence, search, tags, and pinned notes.
- [ ] Adapt the floating-panel and tray experience to each platform's windowing behavior.
- [ ] Establish installation, update, and compatibility checks for each supported platform.

**Deferred:** Windows and Linux remain targets, but are not current priorities and do not block sync, mobile, or capture features. Revisit their delivery order and Linux desktop support after the higher-priority work.

**Acceptance:** each released desktop client reliably reads and edits the shared note format and passes its platform-specific installation and compatibility checks.

## How this roadmap becomes work

Each milestone should be broken into scoped issues with acceptance criteria before implementation. Changes go through pull requests and relevant checks; only shipped work is marked complete. Prototypes can overlap once shared contracts are settled, but a later feature should not delay reliability fixes.

Have a use case or a different priority? [Open an issue](https://github.com/eminuckan/Nook/issues) and describe what you want to do with Nook. See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow.
