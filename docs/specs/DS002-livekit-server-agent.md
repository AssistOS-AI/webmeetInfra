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

The manifest pins the bridge-compatible multi-architecture index
`docker.io/assistos/livekit-server-agent@sha256:012bb28b82300a4e0b720decb6d3b023fc2f26c7a2665832bf1baaeb5b2bb6f9`,
originally published as `webmeet-infra-331fbd1`. Every profile uses that exact
index. The mutable `webmeet-infra` tag is forbidden because it can move to an
image built for a different supervisor contract.

The image is built and published by the manual GitHub Actions workflow
`publish-livekit-server-agent.yml` in `AssistOS-AI/container-image-builds`.
The workflow is `workflow_dispatch` only. It checks out this repository as the
build context and uses
`container-image-builds/images/livekit-server-agent/Dockerfile` as the
centralized Dockerfile. Docker Hub authentication uses the `DOCKERHUB_TOKEN`
secret in `AssistOS-AI/container-image-builds`. The workflow publishes the raw
`webmeet-infra` tag and a source-qualified `webmeet-infra-<sha>` tag through
`docker/setup-buildx-action`, `docker/metadata-action`, and
`docker/build-push-action` with `provenance: false`. The workflow publishes a
multi-architecture image for `linux/amd64` and `linux/arm64` so Apple
Silicon/aarch64 Podman machines pull a native image instead of running Redis
and the media stack through QEMU emulation.

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
   profiles may detect the workstation IPv4 address unless
   `WEBMEET_LOCAL_PUBLIC_HOST` or `WEBMEET_LIVEKIT_NODE_IP` is set. Those
   profiles do not publish media ports from the manifest; media-enabled local
   testing requires an explicitly managed UDP plane outside this manifest.
4. LiveKit Egress (`egress`) using `EGRESS_CONFIG_FILE` pointing at the
   generated `/working-data/generated/egress.yaml`, then waits for the
   configured Egress health port.
5. In the `prod` profile only, Nginx (`nginx`) using
   `/working-data/generated/nginx.conf` (which includes
   `/working-data/generated/livekit.conf`) and a Certbot renewal loop gated by
   `WEBMEET_CERTBOT_AUTO_ISSUE`. Nginx waits for the TLS certificate to appear
   before binding ports.
6. A small in-container health endpoint on `WEBMEET_INFRA_HEALTH_PORT`
   (default `17000`) for diagnostics. The manifest does not publish it.

The supervisor traps `INT`/`TERM`, stops children cleanly, and exits non-zero
if any required service (`redis-server`, `turnserver`, `livekit-server`,
`egress`, or the health listener) dies unexpectedly.

### Manifest invariants

- `agent`: `sh /code/scripts/start-livekit-server-agent.sh`.
- This is a custom-command agent, so Ploinky does not assign it a primary
  service. Consumers enable it with `no-wait`; readiness is verified by
  service-specific smoke checks rather than a published host port.
- No profile declares `openPorts`, legacy `ports`, or an additional-server
  host port. Authenticated browser signaling uses
  `/base-agent-additional-server/liveKitServerAgent/<signaling-port>/...`.
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
  Signaling is reached through Ploinky's in-container reverse relay. These
  profiles do not publish signaling, media, TURN, Egress, Redis, or health
  ports from the manifest.
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

| Profile  | Network         | Browser signaling locator | Server consumer URL pattern                       |
|----------|-----------------|---------------------------|---------------------------------------------------|
| default  | bridge `webmeet`| `liveKitServerAgent:7880` | `http://liveKitServerAgent:7880`, `:7980`         |
| dev      | bridge `webmeet`| `liveKitServerAgent:17880`| `http://liveKitServerAgent:17880`, `:7980`        |
| prod     | host networking | `liveKitServerAgent:7880` | `http://host.containers.internal:7880`/`:7980`    |

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

- Browsers receive a route-key/container-port locator from `webmeetAgent`,
  resolve it with Ploinky's authenticated locator endpoint, and connect through
  the same-origin reverse-proxy WebSocket route. They do not receive a private
  LiveKit URL.
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
path. The default and dev profiles continue to use bridge networking for
workstation control-plane testing and do not declare host port publication.
Production signaling still enters through the Ploinky reverse relay; host
networking is retained for the separately reviewed direct media plane.

### Question #3: Why do consumers enable this agent with `no-wait`?

Response:
This agent uses a custom supervisor command and therefore has no primary
Ploinky service. Its health endpoint is container-confined, so the generic
primary readiness gate cannot probe it. `no-wait` lets dependency startup
continue; routed signaling and the in-container health script provide the
targeted operational checks.

## Conclusion

`liveKitServerAgent` owns the WebMeet runtime contract. It remains valid while
the manifest, supervisor, generated config layout, derived secrets, and the
profile-specific consumer URL patterns continue to match this specification.
