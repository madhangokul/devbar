# DevBar V1 release plan

Target: a public, dependency-free macOS 13+ menu-bar app distributed as a signed and notarized universal DMG.

## Product promise

DevBar gives a solo developer a quiet, glanceable view of Vercel projects, live deployments, deployment queues, failures, and state-change notifications. V1 is read-only: it cannot redeploy, cancel builds, change configuration, or write to Vercel.

## V1 scope

### Menu-bar experience

- Status icon reflects the worst current deployment state.
- Issue count shows building, queued, failed, cancelled, or blocked items.
- Muted graphite/slate interface matching the approved mock.
- Overview: healthy, building, queued, and failed counts plus recent deployments.
- Projects: latest state and short deployment history per project.
- Queue: building and queued deployments ordered by start time.
- Notifications: recent state changes and notification preferences.
- Project filter, manual refresh, relative timestamps, and browser click-through.
- No Dock icon; optional Launch at Login setting.

### Vercel integration

- Personal access token and optional team ID stored in macOS Keychain.
- Current Vercel deployments API with fixture-tested decoding.
- REST reconciliation is always the source of truth.
- Refresh on launch, popover open, wake, restored connectivity, and manual action.
- Adaptive polling:
  - 15–20 seconds while a deployment is active.
  - 60 seconds while the popover is open and everything is settled.
  - 3–5 minutes while closed and settled.
  - Exponential backoff with jitter for network failures and `Retry-After` for rate limits.
- Last good snapshot cached in Application Support, capped at 200 items with a seven-day TTL.
- Per-provider errors never remove another provider's data.

### Notifications

- Permission is requested only when the user enables alerts.
- Notify after REST confirmation when a deployment fails, is cancelled/blocked, or becomes ready.
- Initial hydration never generates notifications.
- Transitions are deduplicated by deployment ID and state.
- Production-created/promoted notifications are optional.

### Optional webhook-assisted mode

- Direct polling remains the default and works on every Vercel plan.
- Pro/Enterprise users may self-host a small relay and configure its HTTPS event-stream URL.
- Vercel posts signed webhook events to the relay; the app connects outbound to it.
- The relay validates the raw-body signature, expected team, event type, body size, and event ID.
- It stores only a short-lived event cursor and publishes a minimal “provider changed” hint.
- It never receives or stores the Vercel API token.
- DevBar coalesces hints, fetches the authoritative REST state, then updates the UI.
- A ten-minute reconciliation and adaptive polling remain as recovery paths.
- Relay support may ship as experimental without delaying the direct-mode DMG.

## Architecture

```text
Vercel REST API <-----------------------------+
       |                                      |
       +-- authoritative snapshot --> RefreshCoordinator
                                               |
optional Vercel webhook                        +--> ToolbarStore --> SwiftUI
       |                                       +--> SnapshotCache
       v                                       +--> NotificationService
self-hosted relay -- outbound event hint ------+
```

- `ToolbarProvider`: provider identity, credential fields, and snapshot fetch.
- `RefreshCoordinator`: polling policy, trigger coalescing, backoff, sleep/wake, and connectivity recovery.
- `ToolbarStore`: normalized presentation state and filters.
- `SnapshotCache`: bounded non-secret JSON cache.
- `NotificationService`: authorized, deduplicated state-transition alerts.
- `EventHintSource`: optional provider-neutral event stream.
- `CredentialStore`: Keychain-only secret storage.

Provider implementations do not know about SwiftUI, notifications, scheduling, or webhook transport.

## Permissions and security

### Used by V1

- Outbound internet access for HTTPS and an optional event stream. No permission dialog.
- Keychain generic-password entries for tokens and optional relay credentials.
- Notifications, requested in context and only when enabled.
- Launch at Login, optional and controlled through macOS Login Items.

### Not requested

- No incoming network listener.
- No administrator/root access.
- No Full Disk Access, Files and Folders, Accessibility, Screen Recording, or Automation.
- No camera, microphone, location, contacts, calendar, Bluetooth, or Local Network access.
- No analytics, advertising SDK, or background helper process.

### Release hardening

- Stable proposed bundle ID: `io.github.madhangokul.devbar`.
- App Sandbox with only `com.apple.security.network.client`.
- Hardened Runtime and secure timestamp.
- Developer ID Application signing.
- Apple notarization and stapled ticket.
- No secrets in source, logs, app bundle, cache, CI artifacts, or webhook relay.
- Vercel token remains on the user's Mac and is sent only to Vercel.

## Open-source repository

Proposed repository: `madhangokul/devbar`, public, MIT licensed.

Required files:

- README with screenshots, install/uninstall, permissions, token setup, architecture, and build instructions.
- MIT `LICENSE`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, and `CODE_OF_CONDUCT.md`.
- Issue forms, pull-request template, and CODEOWNERS.
- Architecture, privacy, troubleshooting, and release documentation.
- Expanded ignore rules for build products, signing files, provisioning files, environment files, and local credentials.

Repository settings:

- Issues and private vulnerability reporting enabled.
- Secret scanning and push protection enabled when available.
- Read-only default Actions token.
- Main branch protected from deletion and force pushes.
- Pull requests, passing CI, resolved conversations, and linear history required.
- Zero review approvals initially for a solo maintainer; increase when another maintainer joins.
- `v*` tags protected from update or deletion.

## Build, test, and release automation

### Pull-request CI

- Run on macOS arm64 and Intel runners.
- Build debug and release configurations.
- Run unit and integration tests with no repository secrets.
- Validate package structure, formatting, app metadata, and secret hygiene.
- Upload test results only when useful; no credentials in artifacts.
- Minimal workflow permission: `contents: read`.

### Release path

1. Build release binaries for arm64 and x86_64.
2. Combine them into one universal binary.
3. Assemble a versioned `.app` with icon and Info.plist.
4. Sign with Developer ID Application, Hardened Runtime, timestamp, and minimal entitlements.
5. Verify the signature and entitlements.
6. Create a DMG containing DevBar and an Applications shortcut.
7. Sign the DMG, submit it to Apple, staple the notarization ticket, and verify Gatekeeper acceptance.
8. Generate a SHA-256 checksum.
9. Create a draft GitHub Release and attach the DMG, checksum, release notes, and provenance.
10. Test the downloaded artifact on a clean user account before publishing the release.

The first release is signed and notarized locally. Signing moves to GitHub Actions only after the manual path succeeds and repository secrets are configured safely.

## Test matrix

### Unit and integration

- Decode all Vercel states and incomplete/malformed responses.
- Verify URL construction, bearer header, team ID, limits, and incremental timestamps.
- Cover 200, 401, 403, 429, 500, timeout, cancellation, offline, and invalid JSON.
- Verify provider error isolation and preservation of the last successful snapshot.
- Verify queue ordering, filters, worst-state aggregation, and item caps.
- Verify polling policies, coalescing, cancellation, backoff, and `Retry-After`.
- Verify initial hydration does not notify and each later transition notifies once.
- Verify cache expiry/recovery and prove that it contains no credentials.
- Verify optional relay signature, team, payload size, deduplication, and reconnect behavior.

### UI and system

- Fresh install, no token, invalid token, personal token, and team-scoped token.
- Notification allowed and denied paths.
- Popover, filters, queue, row click-through, menu icon, settings, and Launch at Login.
- Sleep/wake, offline/online, event burst, relay disconnect, and provider disable during refresh.
- VoiceOver labels, keyboard navigation, contrast, reduced motion, and text truncation.

### Distribution and performance

- Install from the notarized DMG on macOS 13, 14, and the current macOS release.
- Verify signatures, Hardened Runtime, entitlements, notarization staple, and Gatekeeper.
- Test uninstall/reinstall and Keychain behavior.
- Target under 40 MB settled idle memory and near-zero idle CPU.
- Confirm no polling wakeups while asleep/offline and no unbounded item/event growth.

## Execution lanes

### Lane A — product and data

- Correct the Vercel client and fixtures.
- Implement refresh coordination, caching, notifications, and lifecycle recovery.
- Add Overview, Projects, Queue, and Notifications state.

### Lane B — native interface

- Replace the prototype palette with approved muted tokens.
- Implement the approved compact popover and settings flows.
- Add accessibility and first-run guidance.

### Lane C — distribution

- Add metadata, icon, entitlements, universal release build, DMG creation, signing, notarization, checksum, and validation scripts.

### Lane D — open source and CI

- Add license, community documentation, contributor/security guidance, CI, release workflow, and repository settings checklist.

Lanes A–D run in parallel. They converge at the test matrix, clean-install verification, GitHub release draft, and final release decision.

## Current blockers discovered on 2026-09-04

- GitHub CLI authentication for `madhangokul` has expired, so the public repository cannot yet be created or pushed.
- Full Xcode is not installed. The active Command Line Tools Swift compiler and SDK builds do not match, so the current machine cannot compile the project reliably.
- No Developer ID Application certificate is installed (`0 valid identities`).
- Apple notarization credentials are not configured.

An unsigned DMG can be produced after fixing the toolchain, but Gatekeeper will warn or block normal users. It is not considered the production V1 release.

## Release definition of done

- Approved UI and all direct-mode V1 features work.
- Automated tests pass on arm64 and Intel.
- Idle resource targets are measured, not estimated.
- No required permission is broader than documented.
- The public repository contains no credentials or signing material.
- A clean Mac can download, install, launch, connect, receive an alert, and uninstall DevBar.
- The GitHub release contains the notarized universal DMG, checksum, release notes, and known limitations.
