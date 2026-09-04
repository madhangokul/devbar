# V2 webhook-assisted updates

Status: deferred. DevBar V1 uses direct Vercel REST reconciliation and requires no hosted DevBar service.

## Why this is V2

V1 keeps installation and trust simple: the Mac stores the Vercel token in Keychain, talks directly to Vercel, and reconciles deployment state every five seconds. The visible HUD advances locally once per second between authoritative responses.

A webhook can reduce detection latency and settled polling, but Vercel must deliver it to a public HTTPS endpoint. A Mac behind NAT, asleep, or moving between networks cannot reliably be that endpoint. Supporting webhooks therefore introduces a relay, relay authentication, reconnect behavior, deployment documentation, and a larger security boundary.

Vercel account webhooks are currently available on Pro and Enterprise plans. See [Setting Up Webhooks](https://vercel.com/docs/webhooks) and the [Webhooks API reference](https://vercel.com/docs/webhooks/webhooks-api).

## Proposed event flow

```text
Vercel
  | signed deployment webhook
  v
public DevBar relay
  | authenticated event hint
  v
DevBar EventHintSource
  | immediate provider refresh
  v
Vercel REST API --> ToolbarStore --> HUD and notifications
```

The webhook is a wake-up hint, not application state. DevBar always fetches the authoritative deployment from the Vercel REST API before changing final status.

The first supported events should be:

- `deployment.created` to discover a deployment and open the HUD quickly.
- `deployment.succeeded` to reconcile completion.
- `deployment.error` to reconcile failure.
- `deployment.canceled` to reconcile cancellation.

Webhooks provide lifecycle events, not a continuous build percentage. During a build, the HUD should continue its local one-second animation and reconcile with Vercel every five seconds. A terminal webhook requests an immediate reconciliation.

## Relay responsibilities

The relay must remain small and stateless where possible:

1. Read the unmodified request body.
2. Verify `x-vercel-signature` using the webhook secret and a constant-time comparison.
3. Enforce a small body limit and an allowlist of event types and Vercel team/project IDs.
4. Deduplicate Vercel event IDs for a short bounded period.
5. Publish only a minimal hint: provider, event ID, deployment ID, event type, and creation time.
6. Never receive, store, or proxy the user's Vercel access token.

DevBar should authenticate its outbound realtime connection with a revocable, device-specific credential stored in Keychain. Logs must not include webhook secrets, device credentials, access tokens, or raw payloads.

## Recommended implementation

For the first implementation, use a self-hosted HTTPS webhook handler plus a private realtime channel. Supabase Realtime is one reasonable transport because the Mac maintains one outbound WebSocket and the relay can broadcast a small event. The transport should remain behind the provider-neutral `EventHintSource` interface so contributors can implement a different relay without changing Vercel, store, or HUD code.

The direct REST path remains mandatory:

- Immediate refresh on an authenticated hint.
- Five-second reconciliation while a deployment is active.
- A slower periodic reconciliation while settled to recover missed events.
- Existing exponential backoff and `Retry-After` behavior after failures.
- Normal launch, wake, network-restoration, popover-open, and manual refresh triggers.

A Cloudflare Tunnel, Tailscale Funnel, or similar tunnel can expose a local listener for development, but it is not the default product architecture. It makes reliability dependent on a machine-specific public tunnel and expands the local network attack surface.

## Open-source and permission impact

Webhook assistance must be optional. Users who do not configure it continue using direct mode with no incoming listener and no additional macOS permission prompts.

The project should initially support a bring-your-own relay. A centrally hosted multi-tenant DevBar relay would require a separate privacy model, tenant isolation, abuse controls, secret rotation, retention policy, service monitoring, and operating budget.

## Delivery checklist

- Implement and test relay signature verification against the raw body.
- Add bounded event deduplication and project/team allowlists.
- Implement one authenticated `EventHintSource` client with reconnect and jitter.
- Connect the source through `RefreshCoordinator.connectEventHints(from:)`.
- Coalesce event bursts into one authoritative REST refresh.
- Add settings for relay URL, device credential, connection state, and a safe test action.
- Test created, succeeded, error, canceled, duplicates, invalid signatures, reconnects, missed events, sleep/wake, and REST fallback.
- Document self-hosting, secret rotation, removal, and failure recovery.

No webhook infrastructure or relay credential is required for V1.
