# Prepublication security review

This was an internal source review, not an independent audit or penetration test. The Linux detector passed 11 tests; Bandit reported no findings in its executable. The Mac's portable structural checks passed but do not exercise AppKit. Native CI results are separate evidence; manual notification/SSH acceptance tests remain necessary.

## Hardening applied

- Forward notification actions request authentication before acting on a locked Mac.
- Distinct service IDs are capped at 512 per connection; exceeding the cap disconnects rather than growing state forever.
- Service notifications are limited to 10 per minute; remaining services can be approved in the menu.
- Removing services clears old notification requests. Changing an existing service's project label, endpoint or pane disconnects to avoid transferring approval context.
- Existing strict host-key checks, key-only SSH, no agent/X11 forwarding, isolated control socket, cleared inherited forwards, bounded streams and explicit approval tokens were inspected.

## Known limitation: Stop is not complete connection revocation

**Stop removes the listener for new connections; an already-open forwarded TCP/WebSocket connection can remain alive.** OpenSSH `-O cancel` does not terminate existing channels. The same applies to automatic cancellation when a service disappears. Use **Disconnect** or quit the app to close the entire SSH master and terminate all forwarding channels. This limitation is important for databases, long-lived browser WebSockets and any sensitive service. Do not treat Stop as a security revocation boundary.

A future implementation may use separately terminable masters per service. Current acceptance tests must include a persistent connection as well as fresh curl requests. Abrupt app crash/orphan-master cleanup also requires native testing; normal quit/timeout cleanup is not proof that all crash scenarios are covered.

## Publication hygiene

Only tracked source/docs are published, not local bytecode/build directories. A limited credential/private-host pattern scan found no matches in source. No third-party runtime dependencies are declared. This does not audit Apple frameworks, Python, OpenSSH or Herdr. No guarantee of vulnerability-free software is made.
