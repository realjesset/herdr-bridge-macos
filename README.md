# Herdr Bridge for macOS

[Download the Apple Silicon DMG](https://github.com/realjesset/herdr-bridge-macos/releases/download/v0.1.0-alpha.1/Herdr.Bridge.dmg) · [All alpha downloads and checksums](https://github.com/realjesset/herdr-bridge-macos/releases/tag/v0.1.0-alpha.1)

Native macOS CI passed: six Swift tests, app build, ad-hoc signature verification and DMG creation. This does not replace interactive UI/notification/security testing. The prebuilt app is **Apple Silicon only**, ad-hoc signed, not notarized. Intel users must build from source.

**Experimental:** read the [security review and remaining limitations](SECURITY-REVIEW.md). **Stop prevents new connections but may leave existing TCP/WebSocket sessions alive; Disconnect or Quit closes all channels.**

A small Mac menu-bar app for bringing remote development services to your Mac over SSH. It shows detected services and forwards a port **only after you click Forward**.

## Which part do I need?

- **This repository is the Mac app.** Install `Herdr Bridge.app` on your Mac (macOS 13 or newer).
- **[herdr-bridge-agent](https://github.com/realjesset/herdr-bridge-agent) is the remote companion.** Install it separately on the machine running your Herdr development sessions, following that repository's requirements and instructions. It reports eligible loopback services to the Mac app.

You need both parts and a working SSH connection. The Mac app does not install the companion, configure SSH, or start remote development servers.

> Experimental software, provided without warranty. It is not security-certified or independently audited. Builds made by the included scripts are ad-hoc signed, not Developer ID signed or Apple-notarized. See [security limits and support](SECURITY.md).

## Install the Mac app

### Option 1: Download a release, if available

1. Open [Releases](https://github.com/realjesset/herdr-bridge-macos/releases). If a release includes a packaged `.app` ZIP or `.dmg` for your Mac's architecture, download that asset. **GitHub's “Source code” ZIP is not an installable app.** A release or prebuilt download may not exist yet; use the source build below if none is available.
2. Expand the ZIP, or open the DMG. Drag **Herdr Bridge.app** into **Applications**. A DMG's Applications shortcut is only a drag-and-drop convenience, not an installer. Eject the DMG afterward.
3. Open **Applications → Herdr Bridge**, or find it in **Launchpad** on macOS versions that provide Launchpad. Look for its network-shaped icon in the **menu bar**; there is no main window or Dock icon. Orange means it has not received a valid detector snapshot; green means the detector is ready, not that a port is forwarded.

Check the release notes for architecture and signing status. Apple Silicon (`arm64`) and Intel (`x86_64`) builds are not interchangeable without additional compatibility support. The build script produces a host-architecture app, not a universal app.

macOS may block an unnotarized download. Do not disable Gatekeeper or remove quarantine protections to force it to run. If you cannot establish trust in a download, do not open it; review and build the source instead, or wait for a suitable signed release. A checksum or ad-hoc signature alone does not establish publisher identity.

### Option 2: Build from source on your Mac

Install Xcode 15 or newer, or compatible Apple Command Line Tools providing **Swift 5.9+**. If needed, request Apple's tools with `xcode-select --install`, then finish that installation before continuing.

In Terminal:

```sh
git clone https://github.com/realjesset/herdr-bridge-macos.git
cd herdr-bridge-macos
bash build-app.sh
open dist
```

The script runs tests, builds the app, validates its bundle metadata, and applies and checks an ad-hoc signature. It does not install the app. Drag **Herdr Bridge.app** from `dist` into Applications, then open it there. There are no third-party Swift package dependencies. Use the `.app` bundle rather than `swift run` for notifications.

### Developer builds from GitHub Actions

[Actions](https://github.com/realjesset/herdr-bridge-macos/actions) is separate from Releases. After a successful **macOS build** run, a logged-in GitHub user with repository access can download its **Artifacts**. Expand the artifact ZIP, then expand the enclosed app ZIP to get `Herdr Bridge.app`. Artifacts expire and may come from unreviewed pull requests; select a trusted commit and check the run's architecture. They are ad-hoc signed development builds, not notarized releases.

Public release assets can normally be downloaded without signing in; Actions artifact downloads require GitHub login. CI does **not** publish releases automatically.

## Prepare SSH and the remote companion

1. Install the [remote companion](https://github.com/realjesset/herdr-bridge-agent) on your development machine. The app expects the executable at `~/.local/bin/herdr-bridge-agent` on that machine.
2. Create or use a dedicated, trusted alias in your Mac's `~/.ssh/config`. This example uses placeholders; replace the hostname, username, and key path with your own:

   ```sshconfig
   Host dev-box
       HostName dev.example.com
       User developer
       IdentityFile ~/.ssh/id_ed25519
       IdentitiesOnly yes
       ForwardAgent no
   ```

3. Verify the server's SSH host-key fingerprint with its administrator or another trusted channel. Connect manually with `ssh dev-box` and accept the host key **only after** it matches. If SSH reports a changed key, investigate; do not blindly delete known-host records. The app requires an already-known host key and will not enroll one.
4. Ensure public-key authentication works without interactive prompts. Unlock/load your key using your normal SSH setup if needed. A simple dedicated alias should pass:

   ```sh
   ssh -o BatchMode=yes -o StrictHostKeyChecking=yes        -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no        -o PreferredAuthentications=publickey dev-box true
   ```

The app uses `/usr/bin/ssh` and your SSH configuration. It never asks for an SSH password and does not forward your authentication agent. Treat SSH configuration as trusted code: options such as `ProxyCommand` or `Match exec` can execute programs. See [SECURITY.md](SECURITY.md).

## Connect and approve a service

1. Click the menu-bar icon, choose **SSH alias**, and enter your alias, such as `dev-box`. Only the alias is remembered; forwarding approvals are not.
2. Click **Connect**. Start an eligible service in your remote Herdr session if none is detected.
3. Open a service's submenu and choose **Forward** or **Ignore**. Until you explicitly choose Forward, that service gets no local forward. Notification permission and clicking a notification's body are **not** forwarding approval.
4. After SSH accepts the forward, the service shows **Active** at `127.0.0.1:PORT` on your Mac. It uses the same port number as the remote service. An occupied port produces an error, not an automatic remap.
5. For an HTTP service, choose **Open HTTP in Browser** to open `http://127.0.0.1:PORT/`. This is a manual HTTP action, not protocol detection. Active confirms the SSH forwarding command succeeded, not that the application is healthy or even speaks HTTP.
6. **Stop** removes the forward, not the remote server. **Disconnect** or **Quit Herdr Bridge** closes the connection and its forwards. Changing the alias also disconnects.

Ignored, stopped, failed, or disappeared/reappeared services are not repeatedly prompted during the same connection. Disconnect and reconnect explicitly to request fresh approvals. There is no automatic reconnect, launch at login, updater, or telemetry.

## Notifications (optional)

Use **Enable / Retry Pending Notifications…** in the app menu, then allow notifications when macOS asks. Use **Send Test Notification** to submit a test that forwards no port. If alerts do not arrive, use **Open Notification Settings…** or **System Settings → Notifications → Herdr Bridge**, and check Focus and banner settings. macOS can suppress delivery even when a request is accepted.

Service notifications offer **Forward** and **Ignore** actions. The menu remains usable if notifications are denied, unavailable, or missed. Ad-hoc builds can have notification identity/permission quirks after rebuilding; launch the app bundle from its stable Applications location.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Nothing appears after launch | Look in the menu bar, not for a window or Dock icon. |
| SSH exits or never becomes ready | Verify the alias, known host key, public-key login, and companion installation in Terminal. The app does not repair SSH configuration. |
| Connected, but no services | Check the companion's detection requirements and whether the service belongs to an eligible Herdr pane. Wildcard/container listeners are outside the companion's intended scope. |
| Forward fails | Check whether another local program already uses the same port and whether the SSH server allows forwarding. |
| Active, but the browser fails | Check the remote application and protocol. Only use the browser action for HTTP services. |
| All forwards disappear | Disconnect, detector failure, malformed output, EOF, or a 15-second snapshot timeout closes the connection. Resolve the cause, then reconnect. |

For development and manual verification, see [DEVELOPMENT.md](DEVELOPMENT.md) and [PROTOCOL.md](PROTOCOL.md). For contributions, see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
