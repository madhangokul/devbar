# Architecture

DevBar is a menu-bar shell with provider plugins. Vercel is the first provider, not a special case embedded throughout the app.

## Principles

- Read-only by default.
- REST snapshots are authoritative.
- One provider's failure cannot blank another provider's data.
- Credentials live in Keychain, never preferences or cache files.
- Background work is bounded, cancelable, and energy-aware.
- Foundation and SwiftUI are preferred over third-party dependencies.

## Main components

### `ToolbarProvider`

Declares a stable identity, presentation metadata, generic credential fields, and one asynchronous snapshot fetch. It maps a service-specific response into provider-neutral toolbar items.

### `RefreshCoordinator`

Owns refresh triggers and policy. It coalesces overlapping triggers, changes polling cadence based on active work and popover visibility, backs off after errors, and reconciles after wake or network restoration.

### `ToolbarStore`

Owns main-actor presentation state: items, errors, filters, aggregate status, last-update metadata, and enabled providers.

### `CredentialStore`

Stores one Keychain item per provider field. A provider receives only its own credential dictionary.

### `SnapshotCache`

Persists a bounded, non-secret last-good snapshot for offline startup. Cache data is visibly marked stale and expires after seven days.

### `NotificationService`

Compares a previously reconciled state with the next authoritative state and emits deduplicated local notifications. Initial hydration never alerts.

### `EventHintSource`

An optional provider-neutral outbound stream. It marks a provider dirty; it never mutates the final UI state directly.

## Refresh policy

| State | Interval |
| --- | --- |
| Active deployment | 5 seconds, with local HUD animation every second |
| Settled, direct mode | 5 seconds |
| V2 webhook-assisted | Immediate hint plus REST reconciliation |
| Offline or rate-limited | Bounded exponential backoff with jitter |

Launch, manual refresh, wake, and restored connectivity trigger immediate reconciliation.

## Adding a provider

1. Add a folder under `DevBar/Providers/<Provider>`.
2. Implement `ToolbarProvider` and map remote states into normalized items.
3. Register one provider value in `ProviderRegistry`.
4. Add decoding, error, and fixture tests.

Core refresh, filter, notification, cache, and settings code must not require provider-specific branches.

## V2 webhook boundary

A menu-bar app cannot reliably receive public webhooks behind NAT or while asleep. Optional webhook-assisted mode therefore uses a small public relay and an outbound event stream.

The relay validates Vercel's signature against the raw body, checks team and event type, deduplicates the event ID, and publishes a small dirty hint. It stores no Vercel token or deployment log. DevBar debounces hints and refreshes through the normal provider API.

Webhook assistance is deferred from V1. See [V2 webhook-assisted updates](V2_WEBHOOK_RELAY.md) for the proposed event flow, security boundary, and delivery checklist.
