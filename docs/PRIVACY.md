# Privacy and permissions

DevBar is designed to keep its permission footprint small and understandable.

## Data flow

- Your Vercel token is stored as a generic password in macOS Keychain.
- Direct mode sends that token only to `https://api.vercel.com` in an Authorization header.
- DevBar fetches deployment metadata needed for its status views.
- A bounded last-good snapshot may be stored in the user's Application Support directory. It contains no access token or webhook secret.
- DevBar includes no analytics, advertising, crash-reporting, or tracking SDK.

## Permissions used

### Outbound network

Required to fetch Vercel status and, if configured, connect to a self-hosted webhook relay. DevBar does not listen for incoming connections.

### Keychain

Required to store the Vercel token, optional Team ID, and optional relay credentials. macOS may ask for Keychain access if the application's signing identity changes.

### Notifications

Optional. DevBar asks only after the user enables alerts. Denying access does not affect deployment tracking.

### Launch at Login

Optional. When enabled, macOS lists DevBar under System Settings → General → Login Items. The user can disable it at any time.

## Permissions not used

DevBar does not request administrator/root access, Full Disk Access, Accessibility, Screen Recording, Apple Events or Automation, Files and Folders, Local Network discovery, camera, microphone, location, contacts, calendar, Bluetooth, or incoming network access.

## Optional webhook relay

The relay receives signed Vercel webhook payloads but never receives the Vercel access token. It publishes only a minimal event hint. DevBar then fetches the authoritative state directly from Vercel.

Each user self-hosts their relay. A centrally hosted multi-tenant relay is outside the V1 trust model.

## Removing DevBar

Quit DevBar and move it from Applications to Trash. Removing the app does not automatically remove Keychain entries. They can be deleted using Keychain Access by searching for `io.github.madhangokul.devbar`.
