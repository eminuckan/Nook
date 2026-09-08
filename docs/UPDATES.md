# Updating Nook

Nook uses [Sparkle 2](https://sparkle-project.org/documentation/) for update
checks, signed downloads, installation, and relaunch. Automatic checks default
to on and can be changed in Settings. Sparkle persists this preference. It
checks daily and shows its standard update window when a release is available;
installation requires the user's action. The menu-bar context menu and Settings
also provide Check for Updates. Preview and command-line development runs never
start the updater.

The updater asks Nook to flush pending note writes before installation. If that
fails, the existing save-error prompt can cancel the update and keep Nook open.

## Release trust and versioning

The feed is hosted at
`https://github.com/eminuckan/Nook/releases/latest/download/appcast.xml`.
Both the feed and ZIP carry Ed25519 signatures checked against `SUPublicEDKey`
in `Resources/Info.plist`. Nook verifies archives before extraction. An HTTPS
connection alone is insufficient to authorize a new executable.

`CFBundleVersion` and `CFBundleShortVersionString` use the release's stable
numeric version, such as `0.2.0`. Increase it for every published release. Local
commit counts and CI run numbers must not be used as competing version sequences.
The stable release workflow rejects prerelease tags. Existing releases from
before Sparkle integration need one manual installation.

The current workflow uses ad-hoc macOS code signing. Ed25519 protects update
authenticity, but this is not Apple Developer ID signing or notarization. For
notarized releases, provide `CODESIGN_IDENTITY` and the notarization credentials
documented by `Scripts/package-release.sh --help`.

## Signing key

After `swift package resolve`, Sparkle tools are in
`.build/artifacts/sparkle/Sparkle/bin/`. Generate the organization's key once:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.nook.quicknotes
```

Keep the private key in the macOS login Keychain and a secure backup. Commit only
the public key. For GitHub Actions, export it with `generate_keys --account
com.nook.quicknotes -x /secure/path/key`, then store the exported file contents
as the repository secret `SPARKLE_PRIVATE_KEY`. Do not print the key or commit
it. Losing this key can break updates for existing installations.

## Build and verify

```sh
swift test
./Scripts/package-release.sh --version 0.2.0 --output-dir dist
./Scripts/generate-appcast.sh 0.2.0 dist
swift Scripts/verify-appcast.swift dist/appcast.xml dist/Nook-0.2.0-arm64.zip Resources/Info.plist 0.2.0
```

The signing script uses the Keychain by default. Set `SPARKLE_PRIVATE_KEY_FILE`
to a protected exported key file when needed. Verification uses only the public
key and checks the actual feed, asset signature, URL, version, and length. It also
proves that changed feed/archive content and different signing keys are rejected.

Packaging preserves Sparkle framework symlinks, embeds all helpers, signs them
from the inside out, and checks the final bundle signature and framework runtime
path. The release workflow builds and verifies all assets before creating a draft
GitHub Release, uploads the feed with the ZIP and DMG, then publishes the complete
release. Publishing changes the stable feed only when its assets exist.

For a runtime acceptance check, install an older Sparkle-enabled release in
Applications, publish the newer signed release, choose Check for Updates, and
complete Install and Relaunch. Confirm the new app version and preserved notes.
This live check covers GUI, helper-process, filesystem, and relaunch boundaries
that cryptographic and build checks alone do not establish.
