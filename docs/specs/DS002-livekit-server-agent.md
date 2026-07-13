---
id: DS002
title: liveKitServerAgent
status: implemented
owner: webmeet-infra-team
summary: Single Ploinky agent that supervises Redis, LiveKit Server, and LiveKit Egress inside one container; TURN now lives in the sibling turnServerAgent.
---

# DS002 - liveKitServerAgent

## Introduction

`liveKitServerAgent` supervises the LiveKit media runtime — Redis, LiveKit
Server, and LiveKit Egress — inside one container. It no longer runs Coturn,
Nginx, or Certbot: TURN/STUN relay behavior moved to the sibling
`turnServerAgent` (see DS004), and the WebMeet signaling edge (TLS
termination, reverse proxying) moved to `basic/web-publishing`. This agent
does not run a TURN relay; its only TURN responsibility is configuring
`rtc.turn_servers` so LiveKit Server can mint expiring credentials and
advertise the sibling relay to browser TURN clients.

## Core Content

### Image and publishing

The manifest pulls `docker.io/assistos/livekit-server-agent:webmeet-infra`
directly. This tag is the default runtime image for every profile.

The image is built and published by the manual GitHub Actions workflow
`publish-livekit-server-agent.yml` in `AssistOS-AI/container-image-builds`.
The workflow is `workflow_dispatch` only. It checks out this repository as the
build context and uses
`container-image-builds/images/livekit-server-agent/Dockerfile` as the
centralized Dockerfile. Docker Hub authentication uses the `DOCKERHUB_TOKEN`
secret in `AssistOS-AI/container-image-builds`. The workflow publishes the raw
`webmeet-infra` tag and an sha-prefixed `webmeet-infra-<sha>` tag through
`docker/setup-buildx-action`, `docker/metadata-action`, and
`docker/build-push-action` with `provenance: false`. The workflow publishes a
multi-architecture image for `linux/amd64` and `linux/arm64` so Apple
Silicon/aarch64 Podman machines pull a native image instead of running Redis
and the media stack through QEMU emulation. The build-push step exposes the
published manifest digest as a job output; a follow-up gate accepts only the
exact `sha256:<64-lowercase-hex>` form and reports the immutable Docker Hub
reference in the workflow log and job summary without replacing the stable
tags. Coturn, Nginx, and Certbot are no
longer part of this image's package list; that reduction is tracked in
`container-image-builds`, a separate repository, not this one.

### Supervised services

The image copies Node 24 and npm from the shared Ploinky Node base for Ploinky's
container runtime-key probe and includes `git`, `make`, and `g++` for Ploinky
dependency-cache bootstrap. It also installs the exact snapshot-pinned
`libc-bin` version that provides `getent`; both the Dockerfile binary gate and
the workflow runtime smoke gate require `getent` because local-profile startup
resolves `turnserveragent` through it. The supervisor
(`scripts/start-livekit-server-agent.sh`) starts the following services in
order, blocking on TCP readiness between steps:

1. Redis (`redis-server`) on `127.0.0.1:6379`, using the generated
   `/working-data/generated/redis.conf`.
2. LiveKit Server (`livekit-server`) using the generated
   `/working-data/generated/livekit.yaml` template, copied to a private
   runtime directory before launch. In `default`/`dev`, the startup script
   resolves the automatic `turnserveragent` alias, asks the kernel route to
   that peer for its source IPv4 address, and replaces the template's node-IP
   marker with the LiveKit address on `webmeet-turn`. This remains unambiguous
   even though LiveKit is attached to two bridges. LiveKit listens on
   `7880` internally in every profile. The generated config's
   `rtc.turn_servers` list points at the sibling `turnServerAgent`, so LiveKit
   itself hands out ephemeral TURN credentials to browsers rather than this
   agent running its own relay.
3. LiveKit Egress (`egress`) using `EGRESS_CONFIG_FILE` pointing at the
   generated `/working-data/generated/egress.yaml`, then waits for the fixed
   internal Egress health port `7980`.

The supervisor traps `INT`/`TERM`, stops children cleanly, and exits non-zero
if any required service (`redis-server`, `livekit-server`, or `egress`) dies
unexpectedly.

### Manifest invariants

- `start`: `sh /code/scripts/start-livekit-server-agent.sh`. This is a
  start-only service, not an MCP agent; declaring the supervisor under
  `agent` would make Ploinky expect an MCP handshake and would bypass the
  script readiness contract.
- `health.readiness.script`: `"readiness.sh"`, a bare filename at this
  directory's root (Ploinky's readiness-script validator rejects any `/` in
  the name). There is no `readiness.protocol` key (setting it to `tcp`/`mcp`
  would silently override script-based readiness) and no published health
  port; `readiness.sh` checks TCP reachability of Redis, LiveKit Server, and
  Egress on their fixed internal ports using `nc`. The pinned image must
  provide `nc`; there is no alternate probe path.
- Generated config is mounted as a single directory from
  `.data/liveKitServerAgent/generated/` into `/working-data/generated`; durable
  state is mounted from `.ploinky/data/webmeet/...` only (the old
  `.ploinky/data/webmeetTls/...` mount is gone with Nginx/Certbot). Preinstall
  rejects symlinked path components for generated config, Redis data, and
  recording storage. It writes each config to a private same-directory
  temporary file and atomically renames it over the final leaf, so a
  pre-existing leaf symlink is replaced rather than followed.
- LiveKit's own API credentials (`WEBMEET_LIVEKIT_API_KEY`/`_API_SECRET`) and
  the TURN shared secret (`WEBMEET_TURN_AUTH_SECRET`) are workspace-scoped
  generated secrets (`sharedGeneratedSecret: true`, `runtime: false`). `WEBMEET_TURN_AUTH_SECRET`
  is declared identically here and in `../turnServerAgent/manifest.json`
  (same env name, no `explicitOverride`, `runtime: false`) so both agents resolve to the same
  launcher-derived value and operator variables cannot inject or split it.
  Preinstall additionally requires all three launcher-derived credentials to
  be exactly 64 lowercase hexadecimal characters before serializing YAML.
  `WEBMEET_TURN_HOST` defaults to `127.0.0.1` in `default`/`dev`; production
  requires an explicit public multi-label DNS hostname and rejects IP
  literals, single-label names, `localhost`, and `.local` names. There is no
  deployment-specific fallback. `WEBMEET_TURN_CREDENTIAL_TTL_SECONDS` is
  owned here because LiveKit creates the ephemeral browser credentials; it
  must be in `1..86400` seconds and fails closed before shell arithmetic on
  overlong input. No separate realm input is declared: Coturn derives its
  realm from the canonical `WEBMEET_TURN_HOST` value.
  Ploinky supplies all three values to host preinstall but omits them and their
  provenance markers from OCI `Config.Env`; later readiness and operator execs
  therefore cannot inherit them. The start script's explicit re-exec scrub is
  retained as defense in depth, while Redis, LiveKit, Egress, and the
  supervisor never require the credential env vars.
  `WEBMEET_LIVEKIT_LOG_LEVEL` defaults to `warn`. In the pinned LiveKit 1.11
  server, `info` emits publisher SDP (ICE credentials, fingerprints, and
  candidate addresses) during RTC startup, so `info`/`debug` are explicit
  sensitive-diagnostic opt-ins and preinstall warns when either is selected.
  Production also requires `WEBMEET_LIVEKIT_NODE_IP` to be unicast IPv4:
  unspecified, loopback, link-local, and multicast values are rejected while
  RFC1918 remains valid for private deployments.
- The root schema-2 network block uses `mode: "bridge"` with primary
  `webmeet-signaling` and secondary `webmeet-turn` attachments. Profiles omit
  `network` and therefore inherit the root block atomically. The manifest does
  not declare aliases: Ploinky derives `livekitserveragent` from the canonical
  agent ID and registers it on both attachments. WebMeet and the publishing
  edge consume ports `7880`/`7980` only through `webmeet-signaling`; Coturn
  shares only `webmeet-turn`. No profile uses host networking.
- `openPorts` is empty in `default`/`dev`, which use TURN relay-only browser
  media. `prod` publishes only LiveKit media: `7881/tcp` and
  `7882-7892/udp` on `0.0.0.0`. The old health port (`17000`), signaling
  port (`7880`), Redis (`6379`), Egress health (`7980`), and (in `prod`) the
  Nginx ports (`80`/`443`) and the old in-agent TURN ports (`3478`,
  `20000-20010`) are gone from `openPorts` entirely.
- The manifest does not declare `containerSecurity.privileged: true`. If a
  future Egress release requires elevated privileges, set
  `containerSecurity.privileged: true` explicitly and update this spec.

### In-container supervisor must not launch sibling agents

Ploinky resolves manifest `enable` edges before this agent's container is
created. A script running inside the container has no access to the workspace
Ploinky CLI and no view of the host's runtime state, so it cannot start or
register sibling agents safely. Every service that needs to run is therefore
either installed in this image and supervised directly, or declared by another
agent that the consumer's manifest enables — including `turnServerAgent`,
which this agent depends on for TURN but does not, and cannot, launch itself.

### Profile-specific networking and consumer URLs

| Profile | Networks | LiveKit media (host) | Consumer URL pattern |
|---------|----------|----------------------|----------------------|
| default | primary `webmeet-signaling`, secondary `webmeet-turn` | none (TURN relay-only) | `http://livekitserveragent:7880` and `:7980` on `webmeet-signaling` |
| dev | primary `webmeet-signaling`, secondary `webmeet-turn` | none (TURN relay-only) | `http://livekitserveragent:7880` and `:7980` on `webmeet-signaling` |
| prod | primary `webmeet-signaling`, secondary `webmeet-turn` | `0.0.0.0:7881`, `0.0.0.0:7882-7892/udp` | `http://livekitserveragent:7880` and `:7980` on `webmeet-signaling` |

`default` and `dev` are now identical in port numbering (previously `dev`
shifted every port by prefixing `1`, e.g. `17880`/`17881`; that shift is
removed since signaling is no longer host-published in either profile and
the media ports collapse to the same numbers).

In `default`/`dev`, the generated config contains a node-IP marker that the
container startup script replaces with the agent's exact `webmeet-turn` IPv4
address, selected from the kernel route to `turnserveragent`. The TURN agent
independently resolves `livekitserveragent` on that trust zone and allows only
that peer. Browsers reach the host-bound local TURN listener,
which relays to LiveKit on the bridge. There is no LAN-IP discovery,
host-runtime inspection, media-port override, or direct local media
publication.

### WebMeet integration boundary

`liveKitServerAgent` owns the media-runtime services only. `webmeetAgent` owns
rooms, invite tokens, participant membership, chat, transcripts, artifacts, AI
dispatch metadata, recording commands, and LiveKit participant JWT issuance.
`turnServerAgent` owns the TURN relay. `basic/web-publishing` owns the
signaling edge (TLS, reverse proxy). The shared boundary is intentionally
narrow:

- Browsers reach LiveKit signaling through `basic/web-publishing`'s reverse
  proxy, not a port this agent publishes directly.
- Browsers reach LiveKit media (the RTC TCP/UDP ports) and TURN relay
  candidates directly; TURN credentials come from LiveKit's own
  `rtc.turn_servers` configuration, ephemeral per-session, never a long-lived
  credential minted by this agent.
- `webmeetAgent` calls LiveKit RoomService, AgentDispatchService, and Egress
  Twirp APIs over `webmeet-signaling` at
  `http://livekitserveragent:7880` in every profile now (previously `:17880`
  in `dev`, before the port collapse).
- LiveKit Egress uses the generated `ws_url` in
  `.data/liveKitServerAgent/generated/egress.yaml` to join rooms as the
  recorder worker and writes MP4 files to the shared
  `.ploinky/data/webmeet/recordings` volume.
- Redis is LiveKit and Egress runtime coordination state. It is not the
  WebMeet application database, room-discovery source, chat store, transcript
  store, or artifact store.
- Guest authorization, admin checks, room visibility, and recording policy
  stay in `webmeetAgent`; this infrastructure agent must not duplicate those
  policies or expose guest-facing HTTP routes.

## Decisions & Questions

### Question #1: Why is the manifest `start` command a shell script instead of a more declarative supervisor (s6, runit, systemd)?

Response:
A shell supervisor avoids adding another runtime dependency to the image and
keeps the contract readable for operators who already know how Ploinky
manifests, preinstall hooks, and health probes work. The `start` key also
classifies the process correctly as a long-running non-MCP service, allowing
Ploinky to execute `health.readiness.script` instead of waiting for an MCP
handshake. The script is small, exits non-zero when a required service dies,
and traps `TERM` so Ploinky's restart semantics still apply. If observability
requirements grow, the supervisor can be replaced without changing the
manifest contract or consumer-facing URLs.

### Question #2: Why does the `prod` profile no longer use host networking?

Response:
Host networking existed to let LiveKit observe real client addresses on its
server-initiated SRTP send path (bridge-mode UDP used to rewrite the source
address in a way receivers would drop) and to let the in-agent Nginx bind
`80`/`443` directly. Nginx is gone from this agent entirely now — the
signaling edge moved to `basic/web-publishing` — removing the second reason.
For the first reason, `prod`'s media ports are published directly on
`0.0.0.0` from the bridge network (not host mode), matching how `default`
and `dev` already worked; this keeps all three profiles on one consistent
networking model (the same two schema-2 bridges, no `host` mode anywhere) instead of
special-casing production.

### Question #3: Why is the readiness probe a script instead of `tcp`/`mcp`?

Response:
The previous `readiness.protocol: "tcp"` probed a standalone Python listener
on `17000`. That listener, its published port, and its Python dependency are
gone. `health.readiness.script: "readiness.sh"` checks Redis, LiveKit Server,
and Egress directly on fixed internal ports using the image-contract `nc`
binary, without publishing or maintaining a fourth listener.

### Question #4: Why are default/dev relay-only instead of publishing local LiveKit media ports?

Response:
Publishing LiveKit's media ports only on host loopback while advertising a
container or LAN address produces unreachable direct ICE candidates. Rather
than guess a host address or add a hidden publication override, local profiles
use the already-required TURN service as their deterministic media path. The
browser reaches TURN on host loopback; TURN reaches the exact LiveKit bridge
address allowed by its fail-closed peer ACL. Multi-machine/LAN browser access
is intentionally not part of the local profile contract.

### Question #5: Why can the TURN shared secret not be explicitly overridden?

Response:
The credential is an internal workspace-owned trust link, not an external
provider credential. Allowing an explicit value would let two independently
started agents drift and would admit arbitrary text into both LiveKit YAML and
Coturn configuration. Both manifests therefore require the same
launcher-derived `sharedGeneratedSecret` with `runtime: false`, while the
trusted host hooks and TURN startup-file boundary also validate its exact
generated encoding before materializing configuration.

## Conclusion

`liveKitServerAgent` owns the LiveKit media-runtime contract (Redis, LiveKit
Server, Egress) only. It remains valid while the manifest, supervisor,
generated config layout, derived secrets, TURN-client configuration, and the
profile-specific consumer URL patterns continue to match this specification;
while OCI and sandbox runtime environments omit credentials already materialized in config;
and while `turnServerAgent` (DS004) and `basic/web-publishing` continue to
own TURN relay and signaling-edge responsibilities respectively.
