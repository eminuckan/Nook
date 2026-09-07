# Contributing to Nook

Thanks for taking a look. Nook is a small personal project, so focused pull requests are easier to review and merge than broad rewrites.

## Before you start

1. Fork the repository and create a branch for your change.
2. Keep the local-first behavior intact. Notes and note content should not leave the Mac unless a future change explicitly introduces that feature and documents it.
3. For user-facing changes, add a short entry under the next version in `CHANGELOG.md`.

## Checks

Run these commands from the repository root:

```sh
swift build -c release
git diff --check
```

If you change the packaging workflow, also run:

```sh
./Scripts/package-release.sh --version 0.1.0 --output-dir /tmp/nook-dist
```

The packaging script is macOS-only because it uses `codesign`, `ditto`, and `hdiutil`.

Release tags are built by GitHub Actions and currently produce ad-hoc assets
for local use. If notarized distribution is enabled later, configure the
Developer ID and App Store Connect secrets documented in the README; never
commit certificates, private API keys, or notarization credentials.

## Pull requests

Explain what changed, how you checked it, and include a screenshot for visual changes when it helps. Keep commits and pull request titles in English so the project history stays consistent.
