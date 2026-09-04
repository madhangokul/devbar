# Security policy

## Supported versions

Until the first stable release, only the latest published DevBar version receives security fixes.

## Reporting a vulnerability

Please do not open a public issue for credential exposure, signature validation, update-channel, Keychain, or webhook vulnerabilities.

Use GitHub's **Report a vulnerability** option under the repository Security tab. Include affected versions, impact, reproduction steps, and any proposed mitigation. You should receive an acknowledgement within seven days.

## Security boundaries

- Vercel access tokens are stored in macOS Keychain and sent only to Vercel over HTTPS.
- The application is read-only and does not trigger or cancel deployments.
- Cached snapshots contain deployment metadata but no credentials.
- The optional webhook relay never receives the Vercel access token.
- Official releases are Developer ID signed, notarized, stapled, and published with a SHA-256 checksum.

Do not trust binaries from unofficial mirrors.
