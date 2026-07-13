# turnServerAgent

Single Ploinky agent that runs Coturn as the WebMeet TURN/STUN relay, on its
own, separate from `liveKitServerAgent`.

Authentication uses Coturn's shared-secret REST/ephemeral mechanism
(`use-auth-secret` / `static-auth-secret`), not static long-term credentials.
LiveKit Server mints short-lived `timestamp:label` / `HMAC-SHA1` credentials
from the shared secret and hands them to browser TURN clients; nothing
long-lived is handed to a browser.

## Image

```
docker.io/coturn/coturn@sha256:0c0e8fc0c263b85a134e9e4242b5e46e1f4c077c5029633511191c05b5c2c814
```

This digest corresponds to the upstream tag `coturn/coturn:4.14.0-r0-debian`
(a manifest-list digest, independently verified against the Docker Hub
registry v2 API). The manifest pins by digest rather than tag because tags
are mutable and not human-derivable from the digest alone. This agent does
not build a custom image; it pulls the upstream Coturn image directly.

## Files

- `manifest.json` — Ploinky manifest with `default`, `dev`, and `prod`
  profiles
- `scripts/hooks/preinstall.sh` — host-side validation for quotas, canonical
  peer inputs, external address, and production TLS material
- `scripts/start-turn-server-agent.sh` — generates a private, mode-`0600`
  in-container config and executes `turnserver -c <generated-config>`
- `readiness.sh` — root-level Ploinky readiness probe (see `health.readiness`
  in `manifest.json`); process/listener/IPv6/TLS checks and a no-secret STUN
  Binding request against the live UDP listener

## Auth model

`static-auth-secret` is generated once per workspace via Ploinky's
`sharedGeneratedSecret: true`, `runtime: false` mechanism under the env name
`WEBMEET_TURN_AUTH_SECRET`, declared identically in this manifest and in
`../liveKitServerAgent/manifest.json` so both agents resolve to the exact
same value without either one hard-coding it. Host preinstall atomically writes
the exact value to `.ploinky/data/webmeetSecrets/turn/auth-secret` behind an
owner-only parent. Ploinky mounts the fixed leaf directory read-only and omits
the value from OCI environment metadata; container startup writes it into a
private in-container `turnserver.conf`. It is never passed on a command line
or logged. Readiness deliberately uses no
credential-bearing client argument because sibling workloads in a nested
ploinky-box can observe the enclosing `/proc`. Relay-only browser E2E proves
REST authentication and the peer ACL.

The generated secret cannot be operator-overridden. Host validation and the
fixed startup-file boundary require its exact generated hexadecimal encoding
before config serialization. Quota, bandwidth, rate, allocation-lifetime, and nonce
overrides are bounded at both boundaries; overflow-length values fail before
shell arithmetic.

## Peer ACL (fail-closed)

The runtime config denies the complete IPv4 and IPv6 spaces, then explicitly
allows exactly one canonical LiveKit IPv4 peer. In `prod`,
`WEBMEET_TURN_ALLOWED_PEER_IPS` must be the same single bare IPv4 or `/32` as
`WEBMEET_LIVEKIT_NODE_IP`; disagreement, broader input, or
unspecified/loopback/link-local/multicast addresses fail closed. RFC1918 is
valid for private deployments. In
`default`/`dev`, the startup script waits for Ploinky's automatic,
canonical-ID-derived `livekitserveragent` alias on `webmeet-turn` to resolve
to exactly one IPv4 address. Neither manifest declares aliases. It never inspects
the host container engine or starts another agent.

## TLS (prod only)

`prod` terminates TURN/TLS on Coturn's `tls-listening-port=5349`, mapped to
the public `443/tcp` (a DNS-only/grey-cloud record, not proxied through the
same Cloudflare tunnel/edge as WebMeet signaling). `preinstall.sh` fails
closed before the container starts if the certificate at
`WEBMEET_TURN_TLS_CERT_PATH` is missing, unreadable, expired
(`openssl x509 -checkend 0`), or does not cover `WEBMEET_TURN_HOST`
(`openssl x509 -checkhost`); there is no self-signed fallback. Certificate
issuance/renewal itself is out of this agent's scope — it expects a cert
already present at the mounted path.
Production also rejects IP-literal, local, and single-label TURN hostnames,
and rejects symlinked TLS path components before reading or changing modes.

## Profiles

| Profile | Network | TURN listener (host) | Relay ports (host) | TLS |
|---------|---------|----------------------|--------------------|-----|
| default | primary bridge `webmeet-turn` | `127.0.0.1:3478` (tcp+udp) | `127.0.0.1:20000-20127/udp` | disabled (`no-tls`/`no-dtls`) |
| dev | primary bridge `webmeet-turn` | `127.0.0.1:3478` (tcp+udp) | `127.0.0.1:20000-20127/udp` | disabled (`no-tls`/`no-dtls`) |
| prod | primary bridge `webmeet-turn` | `0.0.0.0:3478/udp`, `0.0.0.0:443/tcp`→`5349` (internal) | `0.0.0.0:20000-20127/udp` | required, fail-closed |

Plaintext TCP `3478` is never published in `prod`.

## Validation

```sh
cd ../
find turnServerAgent -name '*.json' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null
bash -n turnServerAgent/scripts/start-turn-server-agent.sh
bash -n turnServerAgent/scripts/hooks/preinstall.sh
bash -n turnServerAgent/readiness.sh
```

The unit suite checks manifest and generated-config contracts. Runtime
verification should use the exact digest above and must cover repeated
readiness, wrong-secret rejection, an allowed UDP relay, a denied noncanonical
peer, IPv4-only listeners, and production TLS with the certificate mount
read-only. There is no build step for this agent because it pulls the upstream
image unmodified.
