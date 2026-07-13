# liveKitServerAgent

Single Ploinky agent that supervises the LiveKit media runtime in one
container.

The supervisor in `scripts/start-livekit-server-agent.sh` starts and watches:

- Redis (state for LiveKit and Egress)
- LiveKit Server (SFU)
- LiveKit Egress (recordings and composite output)

TURN/STUN relay behavior lives in the sibling `../turnServerAgent` agent, not
here. The generated `livekit.yaml` advertises `rtc.turn_servers` pointing at
`turnServerAgent` using a shared secret (`WEBMEET_TURN_AUTH_SECRET`) so
LiveKit Server can mint and hand browsers ephemeral TURN credentials without
either agent hard-coding a long-lived one. Signaling TLS termination (Nginx,
Certbot) also no longer lives here; the WebMeet signaling edge is
`basic/web-publishing`.

Preinstall writes those credentials only into the owner-only generated config.
It rejects symlinked workspace storage paths, atomically replaces final config
leaves, and accepts only Ploinky's generated credential encoding. The shared
TURN secret has no operator-override path. The three generated credentials use
`runtime: false`, so Ploinky exposes them to preinstall but omits them from OCI
environment metadata and later execs. The runtime script's re-exec scrub is
retained as defense in depth.

Production accepts only a public multi-label TURN DNS hostname and caps TURN
credential lifetime at 86400 seconds; local profiles retain loopback defaults.

LiveKit logging defaults to `warn`: this pinned release includes publisher SDP
in its `info` RTC-session event. Operators may explicitly select `info`/`debug`
for sensitive diagnostics, and preinstall emits a warning when they do.

The supervisor does not start sibling Ploinky agents. Ploinky resolves manifest
`enable` edges before the container is created, so the in-container script can
only manage processes that already exist inside this image.

## Image

```
assistos/livekit-server-agent:webmeet-infra
```

The manifest pulls
`docker.io/assistos/livekit-server-agent:webmeet-infra@sha256:e8aee1f63763a3dcb427f47d3e0aab78b7932a8c1d6140fce43f7bde960b47f8`
as the immutable default runtime image for every profile.

The image is published through `publish-livekit-server-agent.yml` in
`AssistOS-AI/container-image-builds` (manual `workflow_dispatch` only). That
workflow checks out this repository as the build context, uses the centralized
Dockerfile from `container-image-builds/images/livekit-server-agent/Dockerfile`,
and publishes `linux/amd64` plus `linux/arm64` variants. The stable tags remain
available while the workflow exposes, validates, and reports the pushed
manifest's immutable sha256 reference. It uses the
`DOCKERHUB_TOKEN` secret in `AssistOS-AI/container-image-builds`; do not store
the token in any repo.

## Files

- `manifest.json` — Ploinky manifest with `default`, `dev`, and `prod` profiles
- centralized Dockerfile — final image based on `livekit/egress` plus
  `livekit-server`, Node 24 from the shared Ploinky Node base, `redis-server`,
  `tini`, `curl`, snapshot-pinned `libc-bin`/`getent`, and Ploinky
  dependency-cache tools (`git`, `make`, `g++`); source lives in
  `AssistOS-AI/container-image-builds`
- `scripts/start-livekit-server-agent.sh` — in-container supervisor
- `scripts/hooks/preinstall.sh` — host-side generator for runtime config
- `readiness.sh` — root-level Ploinky readiness probe (TCP reachability of
  Redis, LiveKit Server, and Egress)

## Profiles

| Profile | Networks | LiveKit media (host) | Consumer URL pattern |
|---------|----------|----------------------|----------------------|
| default | primary `webmeet-signaling`, secondary `webmeet-turn` | none (TURN relay-only) | `http://livekitserveragent:7880` on `webmeet-signaling` |
| dev | primary `webmeet-signaling`, secondary `webmeet-turn` | none (TURN relay-only) | `http://livekitserveragent:7880` on `webmeet-signaling` |
| prod | primary `webmeet-signaling`, secondary `webmeet-turn` | `0.0.0.0:7881`, `0.0.0.0:7882-7892/udp` | `http://livekitserveragent:7880` on `webmeet-signaling` |

Signaling (port `7880`) is **not** published to the host in any profile
anymore; it is only reachable over the `webmeet-signaling` bridge at the
automatic `livekitserveragent` alias. Ploinky derives that alias from the
canonical agent ID; the manifest does not declare aliases. The separate
`webmeet-turn` attachment is the only trust zone shared with `turnServerAgent`.
`basic/web-publishing` is the signaling edge that proxies to it. Only
production WebRTC media is published directly to the host. Local
`default`/`dev` profiles use deterministic relay-only media: the browser
reaches TURN on host loopback, and TURN relays to LiveKit's exact `webmeet-turn`
IPv4 address. Local LAN/multi-machine browser access is outside this profile
contract; there is no hidden host-IP or port-publication override.

## Validation

```sh
cd ../
find liveKitServerAgent -name '*.json' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null
bash -n liveKitServerAgent/scripts/start-livekit-server-agent.sh
bash -n liveKitServerAgent/scripts/hooks/preinstall.sh
bash -n liveKitServerAgent/readiness.sh
```

To build the image locally with Docker:

```sh
docker build \
  -t assistos/livekit-server-agent:webmeet-infra \
  -f ../container-image-builds/images/livekit-server-agent/Dockerfile \
  liveKitServerAgent
```

Use Podman with the same arguments if Podman is the configured runtime.
