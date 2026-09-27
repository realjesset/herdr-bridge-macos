# Security and support policy

## Status and support scope

Herdr Bridge is experimental development tooling, supplied **as is** under the MIT license. It is not security-certified, independently security-audited, or approved for regulated or production-critical use. There is no support SLA, guaranteed response time, or promised security-update window. Best-effort maintenance targets the current default branch; older snapshots and CI artifacts are not maintained release lines.

The intended Mac target is macOS 13+ with the matching remote companion protocol. A build on one CI runner is not proof that all supported OS versions, architectures, notification configurations, or SSH environments work. End-to-end behavior requires manual verification.

## Trust boundaries and limits

- **Explicit approval is required.** New services are pending until you choose Forward in the menu or a notification action. Approvals belong to the current connection and service instance, and do not persist across reconnects. Enabling notifications is not forwarding approval.
- **SSH remains trusted infrastructure.** The app uses your system SSH client, local key setup, trusted host-key database, and SSH configuration. It requires known host keys and noninteractive public-key authentication. It does not enroll keys, accept passwords, or forward your authentication agent.
- **SSH configuration is executable configuration.** `ProxyCommand`, `ProxyJump`, and `Match exec` can run or depend on other programs. The app is not sandboxed and does not make untrusted SSH configuration safe. Use a dedicated minimal alias when practical.
- **The remote account and companion must be trusted.** Protocol validation restricts advertised endpoints to remote loopback and ports 1024–65535; it does not prove the identity, safety, or ownership of a remote process. A compromised host or companion can lie about labels and services. A process can also change behind an approved endpoint.
- **Loopback is not per-user access control.** Approved local listeners bind to `127.0.0.1`, not a public interface. Other programs and potentially other users on the same Mac may reach those ports. Keep application authentication enabled; do not treat a local forward as an application-level security boundary.
- **Active is not a health or safety verdict.** It means SSH acknowledged the forward. The app does not probe protocols, verify HTTP content, or add TLS/authentication to the destination service. Browser opening is an explicit plain-HTTP action.
- **Cleanup is defensive, not a guarantee against every failure.** Normal disconnect, quit, stale/malformed detector streams, and uncertain cancellation close the private master. OS failure or forced termination can interrupt normal cleanup. If a listener remains unexpectedly, investigate the owning process with normal system tools before reconnecting.
- **Metadata may be visible locally.** The SSH alias persists in UserDefaults. Service labels and ports appear in menus and optional notifications, including on the lock screen depending on macOS settings. Avoid sensitive project names and control notification previews. No application telemetry or automatic update mechanism is included.
- **Distribution has limits.** Included scripts use ad-hoc signing, not Developer ID signing or Apple notarization. This checks bundle integrity, not publisher identity. CI artifact availability, successful compilation, and GitHub hosting do not certify a build as safe. Do not disable Gatekeeper or strip quarantine protections to run an untrusted download.

See [PROTOCOL.md](PROTOCOL.md) for validation constraints and [DEVELOPMENT.md](DEVELOPMENT.md) for manual checks. The [remote companion](https://github.com/realjesset/herdr-bridge-agent) has its own installation requirements and trust boundary.

## Reporting a suspected vulnerability

Do not post credentials, private keys, private hostnames/IP addresses, identifying project metadata, or exploit details affecting other users in a public issue.

Use GitHub's **Security → Advisories → Report a vulnerability** for this repository **if private reporting is enabled**. Its availability is not guaranteed. If there is no private reporting button, open a minimal public issue asking the maintainer for a private reporting channel, without exploit details or sensitive data. No private email address or guaranteed response time is advertised here.

Include affected commits/versions, OS and architecture, sanitized reproduction steps, expected versus actual behavior, and impact through the agreed private channel. Ordinary usage problems belong in public issues with sanitized diagnostics. Check the current branch before reporting an already-fixed issue.
