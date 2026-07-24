---
id: DS002
title: liveKitServerAgent
status: implemented
owner: webmeet-infra-team
summary: Single Ploinky agent that supervises Redis, Coturn, LiveKit Server, LiveKit Egress, and (in prod) Nginx + Certbot inside one container.
---

# DS002 - liveKitServerAgent

## Introduction

`liveKitServerAgent` is the only Ploinky agent in this repository. It supervises
the full WebMeet media runtime — Redis, Coturn, LiveKit Server, LiveKit Egress,
and (in the `prod` profile) Nginx plus a Certbot renewal loop — inside one
container.

## Core Content

### Image and publishing

The manifest pulls
`docker.io/assistos/livekit-server-agent@sha256:012bb28b82300a4e0b720decb6d3b023fc2f26c7a2665832bf1baaeb5b2bb6f9`
for every profile. Docker Hub also exposes this image as
`webmeet-infra-331fbd1`. The digest is a multi-architecture index containing
native `linux/amd64` and `linux/arm64` images.

The image contains every service required by this branch. Its bundled
`start-livekit-server-agent.sh` and `livekit-server-agent-health.sh` files are
byte-for-byte identical to the files on the current `webmeetInfra/main`
branch. The image's installed command set includes `livekit-server`, `egress`,
`redis-server`, `turnserver`, `nginx`, `certbot`, `python3`, Node/npm,
`git`/`make`/`g++`, `curl`, `nc`, `tini`, and `getent`.

The mutable `webmeet-infra` tag is not part of this manifest contract because
it may be republished for a different source branch and service topology. A
replacement release must be built from an exact `webmeetInfra/main` revision,
smoke-tested on both supported architectures, checked for the complete command
set and current supervisor scripts, then reviewed and pinned here by immutable
multi-architecture digest before deployment.

### Supervised services

The image copies Node 24 and npm from the shared Ploinky Node base for Ploinky's
container runtime-key probe, includes `git`, `make`, and `g++` for Ploinky
dependency-cache bootstrap, `python3` for the local health listener, and `nc`
for portable TCP readiness checks. The supervisor
(`scripts/start-livekit-server-agent.sh`) starts the following services in
order, blocking on TCP readiness between steps:

1. Redis (`redis-server`) on `127.0.0.1:6379`, using the generated
   `/working-data/generated/redis.conf`.
2. Coturn (`turnserver`) using the generated
   `/working-data/generated/turnserver.conf`, with the external IP resolved
   from `WEBMEET_TURN_HOST` when `WEBMEET_TURN_EXTERNAL_IP=auto`.
3. LiveKit Server (`livekit-server`) using the generated
   `/working-data/generated/livekit.yaml`, listening on the profile-appropriate
   signaling port (`7880` for default/prod, `17880` for dev). Default and dev
   profiles detect the workstation IPv4 address unless
   `WEBMEET_LOCAL_PUBLIC_HOST` or `WEBMEET_LIVEKIT_NODE_IP` is set, so browser
   ICE candidates point at host-published media ports instead of the
   bridge-container address.
4. LiveKit Egress (`egress`) using `EGRESS_CONFIG_FILE` pointing at the
   generated `/working-data/generated/egress.yaml`, then waits for the
   configured Egress health port.
5. In the `prod` profile only, Nginx (`nginx`) using
   `/working-data/generated/nginx.conf` (which includes
   `/working-data/generated/livekit.conf`) and a Certbot renewal loop gated by
   `WEBMEET_CERTBOT_AUTO_ISSUE`. Nginx waits for the TLS certificate to appear
   before binding ports.
6. A small health endpoint bound to `0.0.0.0:${WEBMEET_INFRA_HEALTH_PORT}`
   (default `17000`), used as the first published port and therefore as the
   target of Ploinky's `readiness.protocol: "tcp"` probe.

The supervisor traps `INT`/`TERM`, stops children cleanly, and exits non-zero
if any required service (`redis-server`, `turnserver`, `livekit-server`,
`egress`, or the health listener) dies unexpectedly.

### Manifest invariants

- `agent`: `sh /code/scripts/start-livekit-server-agent.sh`.
- `readiness.protocol`: `"tcp"`.
- The health port is first in every profile's `ports` list so the readiness
  gate probes the supervisor, not the LiveKit signaling port.
- Generated config is mounted as a single directory from
  `.data/liveKitServerAgent/generated/` into `/working-data/generated`; durable
  state is mounted from
  `.ploinky/data/webmeet/...` and `.ploinky/data/webmeetTls/...`.
- LiveKit shared API credentials and the TURN shared secret are
  workspace-scoped generated secrets. All consumers declare the same env names
  with `sharedGeneratedSecret: true`; no
  profile may generate hard-coded development credentials.
- Default and dev profiles use the bridge network `webmeet` with the alias
  `liveKitServerAgent`. Consumers reach LiveKit at `liveKitServerAgent:7880`
  (or `:17880` in dev) and Egress at `liveKitServerAgent:7980`. Browser-facing
  LiveKit signaling, media, and TURN ports are intentionally published on
  `0.0.0.0` for these local profiles while Redis, Egress health, and the
  supervisor health port remain loopback-only. The SFU and Coturn advertise the
  detected workstation IPv4 address so Firefox on macOS/Podman can form usable
  ICE pairs; loopback-only candidates are not reliable in that browser/runtime
  combination.
- The `prod` profile uses `network.mode: "host"` to preserve LiveKit's UDP
  WebRTC path and to give Nginx direct ownership of ports 80/443. Sibling
  bridge consumers reach the runtime through `host.containers.internal` in prod.
- The manifest does not declare `containerSecurity.privileged: true`. If a
  future Egress release requires elevated privileges, set
  `containerSecurity.privileged: true` explicitly and update this spec.

### In-container supervisor must not launch sibling agents

Ploinky resolves manifest `enable` edges before this agent's container is
created. A script running inside the container has no access to the workspace
Ploinky CLI and no view of the host's runtime state, so it cannot start or
register sibling agents safely. Every service that needs to run is therefore
either installed in this image and supervised directly, or declared by another
agent that the consumer's manifest enables.

### Profile-specific networking and consumer URLs

| Profile  | Network         | Health port (host) | LiveKit signaling | Consumer URL pattern                       |
|----------|-----------------|--------------------|-------------------|--------------------------------------------|
| default  | bridge `webmeet`| 127.0.0.1:17000    | 0.0.0.0:7880      | `http://liveKitServerAgent:7880`, `:7980`  |
| dev      | bridge `webmeet`| 127.0.0.1:17000    | 0.0.0.0:17880     | `http://liveKitServerAgent:17880`, `:7980` |
| prod     | host networking | 127.0.0.1:17000    | 0.0.0.0:7880      | `http://host.containers.internal:7880`/`:7980` |

Default and dev LiveKit generated config includes `rtc.node_ip` set to the
detected workstation IPv4 address unless `WEBMEET_LIVEKIT_NODE_IP` is
explicitly set. The same detected address seeds `WEBMEET_PUBLIC_LIVEKIT_URL`,
`WEBMEET_TURN_EXTERNAL_IP`, and `WEBMEET_TURN_HOST` when those values are
missing or still point at loopback. `WEBMEET_LOCAL_PUBLIC_HOST` is the
operator override for this local detection. The `prod` profile does not set
`node_ip` by default; it uses host networking and `use_external_ip` semantics
instead.

### WebMeet integration boundary

`liveKitServerAgent` owns the media-runtime services only. `webmeetAgent` owns
rooms, invite tokens, participant membership, chat, transcripts, artifacts, AI
dispatch metadata, recording commands, and LiveKit participant JWT issuance.
The shared boundary is intentionally narrow:

- Browsers connect to LiveKit through `WEBMEET_PUBLIC_LIVEKIT_URL`, which is
  seeded to `ws://<detected-local-ip>:<signaling-port>` in default/dev
  profiles and the production `wss://` signaling hostname in prod.
- `webmeetAgent` calls LiveKit RoomService, AgentDispatchService, and Egress
  Twirp APIs through `WEBMEET_LIVEKIT_URL`, using
  `http://liveKitServerAgent:7880` in default,
  `http://liveKitServerAgent:17880` in dev, and
  `http://host.containers.internal:7880` in prod.
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

### Question #1: Why is the manifest `agent` command a shell script instead of a more declarative supervisor (s6, runit, systemd)?

Response:
A shell supervisor avoids adding another runtime dependency to the image and
keeps the contract readable for operators who already know how Ploinky
manifests, preinstall hooks, and health probes work. The script is small,
exits non-zero when a required service dies, and traps `TERM` so Ploinky's
restart semantics still apply. If observability requirements grow, the
supervisor can be replaced without changing the manifest contract or
consumer-facing URLs.

### Question #2: Why does the `prod` profile use host networking?

Response:
LiveKit's bridge-mode UDP path rewrites the SFU's server-initiated SRTP
downlink source address to a bridge-local IP, which causes receivers to drop
the downlink. Host networking puts LiveKit directly in the host's network
namespace so it observes real client addresses on its server-initiated send
path. Host networking also lets Nginx bind 80/443 directly without giving the
container `CAP_NET_BIND` on a bridge. The default and dev profiles continue
to use bridge networking for workstation use, but they publish only the
browser-facing LiveKit/TURN ports beyond loopback and advertise the detected
workstation IPv4 address so browsers do not have to reach bridge-container
addresses directly.

### Question #3: Why is the readiness probe `tcp` instead of `mcp`?

Response:
This agent does not expose an MCP server. Its primary surface is a TCP health
endpoint at `WEBMEET_INFRA_HEALTH_PORT`. Selecting `readiness.protocol: "tcp"`
makes the Ploinky probe stop as soon as the supervisor accepts a TCP
connection, which only happens after Redis, Coturn, LiveKit, and Egress have
been started in order.

## Conclusion

`liveKitServerAgent` owns the WebMeet runtime contract. It remains valid while
the manifest, supervisor, generated config layout, derived secrets, and the
profile-specific consumer URL patterns continue to match this specification.
