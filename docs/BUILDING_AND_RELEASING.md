# Building and releasing

This guide assumes no prior macOS development experience.

## Install the toolchain

Install the current stable Xcode from the Mac App Store. Wait until `/Applications/Xcode.app` exists; an `.appdownload` file means installation is incomplete.

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
swift --version
```

## Run locally

```sh
swift test
./script/build_and_run.sh
```

The run script stops an existing DevBar process, creates a local application bundle, and launches it. Local development does not require notarization.

## Distribution vocabulary

- **Code signing** identifies the developer and protects the application from modification.
- **Hardened Runtime** enables additional runtime security checks required for notarization.
- **Notarization** submits the application to Apple for automated security checks.
- **Stapling** attaches Apple's notarization ticket to the distributed file.
- **Gatekeeper** checks downloaded software before allowing it to run.
- **Universal binary** contains native Apple Silicon and Intel code.
- **DMG** is the disk image users open to copy DevBar into Applications.

## Create an unsigned local DMG

Unsigned builds are suitable only for local testing. Gatekeeper warns or blocks other users.

```sh
./script/package_release.sh --unsigned 0.1.0
```

## Prepare Developer ID

A public direct-download release requires an active Apple Developer Program membership and a **Developer ID Application** certificate with its private key installed in Keychain. A Developer ID Installer certificate is unnecessary for a DMG.

Confirm the signing identity:

```sh
security find-identity -p codesigning -v
```

Store notarization credentials locally:

```sh
xcrun notarytool store-credentials "DevBar-notary" \
  --apple-id "APPLE_ACCOUNT_EMAIL" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Never commit certificates, private keys, passwords, or notarization profiles.

## Create a signed and notarized DMG

```sh
export DEVBAR_CODESIGN_IDENTITY="Developer ID Application: LEGAL NAME (TEAM_ID)"
export DEVBAR_NOTARY_PROFILE="DevBar-notary"
./script/package_release.sh --notarize 1.0.0
```

The script builds a universal release, assembles and signs `DevBar.app`, creates and signs the DMG, submits it with `notarytool`, staples the ticket, runs signature and Gatekeeper checks, and writes a SHA-256 checksum.

## Publish

1. Test the DMG on a clean macOS user account.
2. Create an annotated `v<version>` tag.
3. Create a draft GitHub Release.
4. Attach the DMG and `.sha256` file.
5. Document changes and known limitations.
6. Download the uploaded artifact and repeat checksum/Gatekeeper verification.
7. Publish the release.

The first release should be signed locally. Move signing secrets to a protected GitHub Actions release environment only after the manual process is proven.
