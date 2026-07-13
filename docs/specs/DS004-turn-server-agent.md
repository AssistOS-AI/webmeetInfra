---
id: DS004
title: turnServerAgent
status: implemented
owner: webmeet-infra-team
summary: Single Ploinky agent that runs Coturn as the dedicated WebMeet TURN/STUN relay using shared-secret REST/ephemeral auth, with a fail-closed peer ACL and production TLS.
---

# DS004 - turnServerAgent

## Introduction

`turnServerAgent` runs Coturn as its own Ploinky agent, separate from
`liveKitServerAgent`. It replaces the static long-term-credential TURN setup
that used to live inside `liveKitServerAgent` with Coturn's shared-secret
REST/ephemeral mechanism (`use-auth-secret` / `static-auth-secret`), and adds
a fail-closed peer allow-list and production TLS requirement that did not
exist before.

## Core Content

### Image

The manifest pulls `docker.io/coturn/coturn` pinned by digest,
`sha256:0c0e8fc0c263b85a134e9e4242b5e46e1f4c077c5029633511191c05b5c2c814`,
corresponding to the upstream tag `4.14.0-r0-debian` (a manifest-list
digest, independently verified against the Docker Hub registry v2 API).
Pinning by digest avoids depending on a mutable tag; the tag correspondence
is recorded in the manifest's `about` field since the digest itself is not
human-readable. This agent does not build or maintain its own Dockerfile; it
consumes the upstream image unmodified.

### Auth model: shared-secret REST/ephemeral, not static credentials

Coturn is configured with `use-auth-secret` and `static-auth-secret=<value>`.
The secret is declared as `WEBMEET_TURN_AUTH_SECRET`
(`sharedGeneratedSecret: true`, `runtime: false`, without `explicitOverride`) identically in
this manifest and in `../liveKitServerAgent/manifest.json`, so Ploinky's
workspace-scoped generated-secret mechanism produces exactly one shared value
for both agents and ignores operator-supplied replacements
(`ploinky/cli/services/secretVars.js`). The host hook requires the exact
64-character lowercase hexadecimal generated form, then atomically writes it
to `.ploinky/data/webmeetSecrets/turn/auth-secret`. The host parent is mode
`0700`; the mounted leaf directory is mode `0755`, its single file is mode
`0444`, and Ploinky mounts the leaf read-only at `/run/webmeet-turn-secret`.
This lets Coturn's fixed `nobody:nogroup` UID read the startup value while
Ploinky omits the secret and provenance marker from OCI `Config.Env`. Container
startup revalidates the fixed file shape and encoding before writing the secret
into a private in-container `turnserver.conf`. It is never passed on a command
line or logged. Readiness must not invoke `turnutils_uclient -W`/`-w`: nested
ploinky-box workloads can expose sibling process arguments through the
enclosing `/proc` view. Relay-only browser E2E is the required end-to-end proof
that LiveKit-issued credentials authenticate and the exact peer restriction
permits the media path.

After the private config is written, the startup script unsets its shell
variable and explicitly removes any same-named inherited env before `exec` as
defense in depth. The secret is absent from OCI container metadata and later
exec environments; only the bounded host preinstall and startup file/config
materialization paths see it, as documented in DS003.

LiveKit Server mints short-lived credentials from that same secret using the
standard TURN REST API convention:
`username = "<expiry-unix-ts>:<label>"`,
`password = base64(HMAC-SHA1(shared-secret, username))` (verified against
coturn's own `README.turnserver`, "TURN REST API" section). LiveKit hands
those expiring credentials to browser TURN clients. No long-lived TURN
credential is ever generated or handed to a browser.

### Quotas, bandwidth, and rate limits

The following limits are normative defaults and are applied via
`WEBMEET_TURN_*` env vars with the same defaults across `default`/`dev`/`prod`:

| Env var | Coturn directive | Default | Maximum |
| --- | --- | --- | --- |
| `WEBMEET_TURN_USER_QUOTA` | `user-quota` | `4` | `10000` |
| `WEBMEET_TURN_TOTAL_QUOTA` | `total-quota` | `100` | `100000` |
| `WEBMEET_TURN_MAX_BPS` | `max-bps` | `2000000` | `1000000000` |
| `WEBMEET_TURN_BPS_CAPACITY` | `bps-capacity` | `50000000` | `2000000000` |
| `WEBMEET_TURN_UNAUTHORIZED_RPS` | `unauthorized-ratelimit-rps` (with `unauthorized-ratelimit` always on) | `10` | `100000` |
| `WEBMEET_TURN_MAX_ALLOCATION_LIFETIME_SECONDS` | `max-allocate-lifetime` | `3600` | `86400` |
| `WEBMEET_TURN_NONCE_LIFETIME_SECONDS` | `stale-nonce` | `600` | `86400` |

Every value must also be a positive decimal integer. Host preinstall and the
container start script enforce the same ceilings, validate digit-string
length before shell arithmetic, and fail closed on max+1 or overflow-length
input. `total-quota` must remain at least `user-quota`, and `bps-capacity`
must remain at least `max-bps`.

`fingerprint` and `no-multicast-peers` are always set. CLI and RFC5780 support
remain off by Coturn 4.14's secure defaults; the deprecated `no-cli` and
`no-rfc5780` spellings are deliberately not emitted. `listening-port=3478`
and the relay range `20000-20127` are fixed in the
manifest and runtime config so their publication cannot drift from Coturn.
TURN credential TTL belongs to LiveKit's `rtc.turn_servers` configuration and
is therefore declared only by `liveKitServerAgent`. Coturn derives its realm
from the canonical `WEBMEET_TURN_HOST`; neither infra manifest declares a
separate realm variable.

Coturn is restricted to IPv4 by the explicit `listening-ip=0.0.0.0` directive,
the complete IPv6 peer deny described below, and readiness assertions that
reject any IPv6 listener on `3478` or `5349`.

### Peer ACL (fail-closed)

The runtime config first denies the complete IPv4 and IPv6 address spaces,
then explicitly allows exactly one canonical LiveKit peer. Coturn gives an
explicit allow precedence over a deny, making this an allow-list rather than
a block-list. The configured directives are:

- `denied-peer-ip=0.0.0.0-255.255.255.255`
- `denied-peer-ip=::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff`
- `allowed-peer-ip=<canonical-livekit-ip>`

In `prod`, `WEBMEET_LIVEKIT_NODE_IP` is the canonical address and
`WEBMEET_TURN_ALLOWED_PEER_IPS` must contain that same single IPv4 host, either
bare or as `/32`. Missing values, multiple values, broader prefixes, malformed
IPv4, unspecified/loopback/link-local/multicast addresses, or disagreement
between the two values fail closed before startup. RFC1918 addresses remain
valid for private deployments.

In `default`/`dev`, `WEBMEET_LIVEKIT_PEER_HOST` defaults to Ploinky's automatic
canonical-ID-derived alias `livekitserveragent` on `webmeet-turn`. The
container startup script waits up to 60 seconds
for that hostname to resolve to exactly one IPv4 address and uses that address
as the canonical allow. It does not inspect the host container engine or infer
container names, so same-wave startup does not create a host-side ordering or
runtime dependency.

### Production TLS (fail-closed, no self-signed fallback)

`prod` sets `cert=`, `pkey=`, `tls-listening-port=5349`, and `no-dtls`.
`WEBMEET_TURN_HOST` must be a public multi-label DNS hostname; IP literals,
single-label names, `localhost`, and `.local` names fail before TLS checks in
both host and container validation.
Before startup, `preinstall.sh` fails if the certificate at
`WEBMEET_TURN_TLS_CERT_PATH` is missing, unreadable, a symlink, expired
(`openssl x509 -checkend 0`), or does not cover `WEBMEET_TURN_HOST`
(`openssl x509 -checkhost`, which does full SAN/CN/wildcard-aware hostname
matching rather than an ad hoc regex). It also rejects a missing, unreadable,
symlinked, invalid, or certificate-mismatched private key. There is no
self-signed fallback.
Certificate issuance/renewal is out of this agent's scope — it expects a
valid cert already mounted at the fixed container path
`/etc/turnserver/tls/{fullchain,privkey}.pem` (host path
`.ploinky/data/webmeetTls/turn/`), by some other operator- or
infrastructure-managed process. The host parent is mode `0700`; the mounted
leaf and files are readable by Coturn's fixed `nobody:nogroup` UID, while the
manifest mounts the leaf read-only in the container. Every host path component
and both certificate leaves are checked for symlinks and canonical confinement
before validation or `chmod`, so the hook cannot escape the workspace or alter
an external target through a bind-source symlink.

### Production external address (`WEBMEET_TURN_EXTERNAL_IP`, fail-closed, no auto-detection)

This agent runs on the `webmeet-turn` bridge network, not host networking,
in every profile, and production reaches it only through Ploinky's host
port-mapping. Without an explicit `external-ip=` directive, coturn would
advertise its own internal bridge-network address in TURN ALLOCATE
responses instead of the real public address, making every relay allocation
unreachable from the internet — this is the standard "TURN behind NAT"
problem, and `external-ip` is coturn's standard fix for it. `prod` requires
`WEBMEET_TURN_EXTERNAL_IP` as an explicit unicast IPv4 address with no default
and no
auto-detection: there is no safe, generic way for a container to discover
its own public-facing address, so this is deliberately operator-supplied
rather than guessed. Unspecified, loopback, link-local, and multicast values
are rejected; RFC1918 remains valid for private deployments. `default`/`dev`
do not declare it at all — those
profiles are loopback-bound end to end, so there is no address translation
to correct for.

### Readiness (no health port)

`manifest.json` declares no `readiness.protocol` (setting it to `tcp`/`mcp`
would silently override script-based readiness) and instead sets
`health.readiness.script: "readiness.sh"`, a bare filename at this
directory's root (Ploinky's readiness-script validator rejects any `/` in
the name — `ploinky/cli/services/docker/healthProbes.js`). No `openPorts`
entry publishes a health port.

`readiness.sh` runs inside the running container and uses only tools verified
in the digest-pinned image. Missing `awk`, `openssl`, `timeout`, or
`turnutils_stunclient` support is a hard image-contract failure, not a skipped
check. The script checks: the `turnserver`
process is alive (via a pidfile under `/tmp`, world-writable regardless of
the container's non-root UID, plus `kill -0`); the configured listeners are
bound (UDP+TCP `3478`; in `prod` also the internal TLS listener `5349`) using
dependency-free `/proc/net/{tcp,udp}` parsing rather than `ss`/`netstat`/`nc`;
rejects any matching IPv6 listener; in `prod`, revalidates certificate
presence, expiry, hostname, and key match; and performs a no-secret STUN
Binding request against UDP `3478`. Exit is `0` only when every required check
passes. REST authentication, relay allocation, and the exact peer ACL are
proved separately by relay-only browser E2E so no secret enters argv.

### Manifest invariants

- `start`: `sh /code/scripts/start-turn-server-agent.sh`; this is a start-only
  service, not an MCP agent. Declaring the supervisor under `agent` would make
  Ploinky expect an MCP handshake and bypass `health.readiness.script`. The
  supervisor runs only `turnserver -c <generated-config>` and does not attempt
  to launch sibling Ploinky agents (the same constraint documented for
  `liveKitServerAgent` in DS002/DS003 applies here).
- The root schema-2 network block uses `mode: "bridge"` with one primary
  attachment, `webmeet-turn`. Profiles omit `network` and inherit that block
  atomically. The manifest does not declare aliases; Ploinky derives
  `turnserveragent` from the canonical ID. No profile uses host networking.
- `default`/`dev` publish `127.0.0.1:3478` (tcp+udp) and
  `127.0.0.1:20000-20127/udp`, matching the loopback-only local-testing
  convention already used elsewhere in this repository. `prod` publishes
  `0.0.0.0:3478/udp`, `0.0.0.0:20000-20127/udp`, and maps the internal TLS
  listener `5349` to public `443/tcp`. Plaintext TCP `3478` is never
  published in `prod`.
- The manifest sets `entrypoint: /usr/bin/env` so the upstream image's
  argument-evaluating entrypoint cannot reinterpret manifest command text.
- No host volume stores `turnserver.conf`. A generated, required, read-only
  manifest volume carries only `auth-secret` from the owner-confined host
  parent into `/run/webmeet-turn-secret`; the non-root container process then
  creates a mode-`0600` config in its own private `/tmp` directory immediately
  before `exec turnserver -c <config>`.

### WebMeet integration boundary

`turnServerAgent` owns TURN relay behavior only. It has no knowledge of
rooms, participants, invite tokens, or LiveKit's control plane; the only
values it shares with `liveKitServerAgent` are `WEBMEET_TURN_AUTH_SECRET`
(the shared secret) and `WEBMEET_TURN_HOST` (so LiveKit can advertise the
correct `rtc.turn_servers[].host`). `liveKitServerAgent` no longer runs
Coturn itself; see DS002.

## Decisions & Questions

### Question #1: Why is `turnserver.conf` generated inside the container instead of in a host-mounted generated directory?

Response:
The pinned image runs as `nobody:nogroup`. A host directory created mode
`0700` by an arbitrary operator UID would be unreadable to that fixed
container UID, while loosening the config directory would expose the embedded
TURN secret to other host users. The design therefore separates the two
needs: a mode-`0700` host parent protects the small startup secret directory,
its mode-`0755` mounted leaf and mode-`0444` file are read-only and usable by
the fixed UID, and the full `turnserver.conf` remains private and mode `0600`
inside the container.

### Question #2: How does default/dev resolve the exact peer without coupling to a host container engine?

Response:
The startup script resolves Ploinky's canonical-ID-derived
`livekitserveragent` alias through `webmeet-turn` DNS and requires exactly one
IPv4 result. It waits for up to 60
seconds, allowing both agents to start in the same dependency wave, and fails
closed if the name is absent or ambiguous. It never calls a host runtime CLI,
inspects container names, or starts the sibling agent.

### Question #3: Why is TURN's relay port range widened to 128 ports (`20000-20127`)?

Response:
Per explicit instruction, replacing the previous in-LiveKit Coturn's
`20000-20010` (11 ports). The wider range is this agent's alone now, with no
other service competing for ports in that range.

### Question #4: Why are quota and lifetime overrides capped instead of only checked as positive integers?

Response:
Unbounded decimal input can overflow shell arithmetic and can also turn a
misconfigured relay into an unintended high-capacity service. Fixed ceilings
make the policy explicit, keep host and container validation identical, and
ensure absurdly long digit strings fail before numeric comparison.

### Question #5: Why is a public multi-label hostname required only in production?

Response:
Production promises a separate trusted TURN/TLS endpoint, so an IP literal,
`localhost`, `.local`, or a single label cannot satisfy that contract. Local
profiles intentionally retain loopback publication and private bridge DNS because they are
host-loopback deployments and do not claim publicly trusted TLS.

## Conclusion

`turnServerAgent` remains valid while it keeps TURN auth on the shared-secret
REST/ephemeral mechanism, denies both complete address families before
allowing exactly one canonical peer, keeps production TLS fail-closed with no
self-signed fallback, requires the digest-pinned readiness toolchain, and
keeps generated secrets out of runtime environment metadata, process arguments,
and logs while confining the read-only startup file behind an owner-only host
parent.
