# Contributing to DevBar

Thank you for helping make DevBar useful to more developers.

## Before starting

- Search existing issues before opening a new one.
- Discuss large features or new providers in an issue first.
- Keep providers read-only unless a separate security review explicitly approves mutations.
- Do not add a dependency when Foundation, SwiftUI, or AppKit already provides the needed capability.

## Local development

Requirements:

- macOS 13 or later
- Current stable Xcode
- Swift 5.9 or later

```sh
git clone https://github.com/madhangokul/devbar.git
cd devbar
swift test
./script/build_and_run.sh
```

Use `./script/vercel_smoke_test.sh` to validate a Vercel token without storing it in the repository. Never include tokens, webhook secrets, certificates, provisioning profiles, or notarization credentials in commits or issue reports.

## Pull requests

- Keep changes narrowly scoped.
- Add or update tests for observable behavior.
- Run `swift test` and `git diff --check`.
- Explain permissions, network calls, persistence, or background work introduced by the change.
- Update user-facing documentation when behavior changes.

By contributing, you agree that your contribution is licensed under the MIT License.
