# Contributing

Bug reports and focused pull requests are welcome. Support is best-effort; see [SECURITY.md](SECURITY.md) for security reports and limitations.

For a normal bug report, include your macOS version and architecture, app commit/release, companion commit/release, reproduction steps, expected behavior, and actual behavior. Remove private hostnames, IP addresses, usernames, paths, keys, tokens, and sensitive service labels. Use aliases such as `dev-box` and reserved example hosts such as `dev.example.com`.

Read [DEVELOPMENT.md](DEVELOPMENT.md) and [PROTOCOL.md](PROTOCOL.md) before changing behavior. Keep parser tests and docs aligned with code. Coordinate wire-format changes with [herdr-bridge-agent](https://github.com/realjesset/herdr-bridge-agent). Preserve explicit approval, strict host-key checking, loopback-only forwarding, and connection-scoped cleanup.

Run `swift test` and `bash build-app.sh` on macOS. Report exactly which checks you ran and their results; if you only ran structural checks on another OS, say so. UI, notifications, and SSH lifecycle need manual macOS testing. Never substitute a structural check or a green parser test for end-to-end verification.

Do not commit generated `.app` bundles, DMGs, build directories, credentials, or personal machine configuration. Do not add unattended install steps, release publication, broader workflow permissions, or signing credentials without separate maintainer review. Pin GitHub actions to reviewed full commit SHAs.

Contributions are made under the repository's [MIT license](LICENSE).
