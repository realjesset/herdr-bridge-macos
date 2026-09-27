# Development and verification

## Requirements and layout

Use macOS 13+ with Swift 5.9+ (Xcode 15 or a compatible newer toolchain). `Package.swift` has no external packages.

- `Sources/BridgeCore`: Foundation-only protocol parsing and SSH alias validation.
- `Sources/HerdrBridge`: AppKit menu UI, optional native notifications, and SSH lifecycle.
- `Tests/BridgeCoreTests`: Swift parser/validation tests.
- `Tests/source_checks.py`: structural checks, not compilation or runtime tests.
- `Info.plist`: bundle identifier `com.herdr.bridge`, executable `HerdrBridge`, and menu-bar-only app metadata.
- [Remote companion](https://github.com/realjesset/herdr-bridge-agent): separate project; coordinate protocol changes with it.

## Build and test on macOS

From the checkout root:

```sh
swift --version
swift test
bash build-app.sh
open "dist/Herdr Bridge.app"
```

`build-app.sh` also runs `swift test`, makes a release build for the host architecture, assembles the bundle, runs `plutil -lint`, and applies/verifies an ad-hoc code signature. It does not install, notarize, or download third-party packages. Launch the bundle, not `swift run`, to exercise notifications.

On a system without the macOS toolchain, these limited checks are available:

```sh
python3 Tests/source_checks.py
bash -n build-app.sh package-dmg.sh
```

Passing these checks is **not** evidence of Swift compilation, working AppKit UI, notification delivery, or SSH forwarding. No native validation result is implied by this documentation. Inspect an actual CI run for build/test results, and record manual results separately before claiming end-to-end support.

## CI and distribution

`.github/workflows/macos.yml` runs on pushes, pull requests, and manual dispatch using `macos-14`. It runs `swift test` and `bash build-app.sh`, verifies the signature, archives the `.app` with `ditto` to preserve bundle metadata and executable permissions, and uploads the ZIP. The artifact name records the GitHub run commit and actual runner architecture. PR runs normally build GitHub's merge commit, not just the contributor's head commit.

CI has only `contents: read`, does not persist checkout credentials, uses no signing secrets, and never publishes a release. Official actions are pinned to immutable commits resolved from their release tags:

| Action | Release | Commit |
| --- | --- | --- |
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/upload-artifact` | `v7.0.1` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |

These refs were retrieved from the official repositories and their action manifests checked for the inputs used here; this is not an independent audit of action implementation. When updating them, inspect official release notes, resolve tags to full commit SHAs, review compatibility, and update both the workflow and this table. The runner image and its Xcode version can change independently; the workflow logs toolchain versions.

Actions artifacts require GitHub authentication to download and expire after the configured retention period (14 days, subject to repository policy). Download and expand the artifact, then its enclosed app ZIP. These are not public release assets. Do not distribute unreviewed PR builds as trusted releases.

To make an optional DMG **on a Mac**, after building:

```sh
bash package-dmg.sh
```

This creates `dist/Herdr Bridge.dmg` containing the app and an `/Applications` shortcut. It verifies the existing app signature, uses `hdiutil` to create and verify a compressed image, and neither mounts the image nor installs anything. It refuses to overwrite an existing DMG; move the old image aside before rebuilding. A DMG adds no notarization or publisher identity.

A maintainer may manually publish verified assets and architecture/signing notes to a GitHub Release. This repository intentionally has no automated release-publishing workflow. Developer ID signing and notarization require separate credentials and a separately reviewed distribution process; do not describe these ad-hoc builds as notarized.

## SSH and protocol architecture

The detector runs the fixed command `~/.local/bin/herdr-bridge-agent --watch` over a foreground private SSH control master. It must not use `-N`, because that would suppress the detector command. A short randomized socket path in a mode-0700 directory avoids macOS UNIX-domain socket path-length limits. The master clears inherited forwarding rules, disables persistent/background masters, and requires strict host-key/public-key authentication.

Approval uses a multiplexing `-O forward` operation with `-L 127.0.0.1:PORT:HOST:PORT`; remote IPv6 loopback is bracketed. Cancellation uses the same specification. Management requests use `-F /dev/null` so configured forwards are not replayed. The detector master still reads the user's trusted SSH configuration. An absent control socket does not authorize a fallback connection.

Per-connection and per-service tokens reject stale callbacks. Management operations are serialized. Cancellation uncertainty or a management timeout closes the master. A validated snapshot, including an empty snapshot, refreshes the monotonic heartbeat; 15 seconds without one, malformed input, detector error, EOF, or SSH exit closes the session and clears approvals. See [PROTOCOL.md](PROTOCOL.md) for the wire contract and [SECURITY.md](SECURITY.md) for trust boundaries.

## Manual macOS acceptance checklist

Record macOS version, architecture, toolchain, app commit, companion commit, and actual observations. Use disposable development services, never production endpoints.

- [ ] Known-key public-key alias connects; unknown-key and password-only aliases fail without prompting.
- [ ] Inherited local, remote, and dynamic SSH forwards create no listeners on Connect or Forward.
- [ ] No listener exists before approval; an approved listener binds only `127.0.0.1` at the same port. Test remote IPv6 loopback too.
- [ ] An occupied local port produces an error, never Active or a remapped port.
- [ ] Stop immediately after Forward; disconnect/reconnect during activation; disappear/reappear a service; click an old notification. No orphan listeners or stale approvals remain.
- [ ] Detector EOF, malformed/oversized frames, explicit detector errors, and a snapshot pause exceeding 15 seconds close all forwards.
- [ ] Denied notifications leave menu controls working. Retry and test notifications respect macOS permissions and Focus behavior; notification-body clicks do not approve.
- [ ] HTTP opening occurs only on an explicit click; non-HTTP services are not auto-probed.
- [ ] Quit with active forwards removes them. Reopening requires a new connection and new approvals.
- [ ] Verify packaged ZIP/DMG extraction, app launch from Applications, signature verification, and menu behavior on each claimed architecture.

Do not mark these complete solely because the parser tests or CI build passed.
