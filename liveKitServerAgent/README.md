# liveKitServerAgent

Single Ploinky agent that supervises the full WebMeet media runtime in one
container.

The supervisor in `scripts/start-livekit-server-agent.sh` starts and watches:

- Redis (state for LiveKit and Egress)
- Coturn (TURN/STUN connectivity)
- LiveKit Server (SFU)
- LiveKit Egress (recordings and composite output)
- Nginx (TLS terminator, `prod` profile only)
- Certbot renew loop (Let's Encrypt cert renewal, `prod` profile only)
- A small `/` health endpoint on `WEBMEET_INFRA_HEALTH_PORT`

The supervisor does not start sibling Ploinky agents. Ploinky resolves manifest
`enable` edges before the container is created, so the in-container script can
only manage processes that already exist inside this image.

## Image

```
docker.io/assistos/livekit-server-agent@sha256:012bb28b82300a4e0b720decb6d3b023fc2f26c7a2665832bf1baaeb5b2bb6f9
```

The manifest pins that bridge-compatible multi-architecture image index for
every profile. It was originally published as `webmeet-infra-331fbd1`. Do not
replace it with the mutable `webmeet-infra` tag, which may implement a different
supervisor contract.

The image is published through `publish-livekit-server-agent.yml` in
`AssistOS-AI/container-image-builds` (manual `workflow_dispatch` only). That
workflow checks out this repository as the build context, uses the centralized
Dockerfile from `container-image-builds/images/livekit-server-agent/Dockerfile`,
and publishes `linux/amd64` plus `linux/arm64` variants. It uses the
`DOCKERHUB_TOKEN` secret in `AssistOS-AI/container-image-builds`; do not store
the token in any repo.

## Files

- `manifest.json` — Ploinky manifest with `default`, `dev`, and `prod` profiles
- centralized Dockerfile — final image based on `livekit/egress` plus
  `livekit-server`, Node 24 from the shared Ploinky Node base, `redis-server`,
  `coturn`, `nginx`, `certbot`, `tini`, `curl`, and Ploinky dependency-cache
  tools (`git`, `make`, `g++`); source lives in
  `AssistOS-AI/container-image-builds`
- `scripts/start-livekit-server-agent.sh` — in-container supervisor
- `scripts/hooks/preinstall.sh` — host-side generator for runtime config
- `scripts/health/livekit-server-agent-health.sh` — operator smoke check

## Profiles

| Profile | Network                  | Browser signaling locator | Server consumer URL pattern                    |
|---------|--------------------------|---------------------------|------------------------------------------------|
| default | bridge `webmeet`         | `liveKitServerAgent:7880` | `http://liveKitServerAgent:7880`, `:7980`      |
| dev     | bridge `webmeet`         | `liveKitServerAgent:17880`| `http://liveKitServerAgent:17880`, `:7980`     |
| prod    | host networking          | `liveKitServerAgent:7880` | `http://host.containers.internal:7880`/`:7980` |

Default and dev generated LiveKit config advertise the detected workstation
IPv4 address as the SFU ICE node address unless `WEBMEET_LIVEKIT_NODE_IP` is
explicitly set. `WEBMEET_LOCAL_PUBLIC_HOST` overrides detection. Browser-facing
No profile publishes listener ports from the manifest. Browser signaling is
resolved through Ploinky and proxied to the container port. Production host
networking remains the separately reviewed direct media plane.

Sibling bridge consumers reach the agent through the single network alias
`liveKitServerAgent` in default/dev. In prod, the agent uses host networking
and consumers must use `host.containers.internal` (or `127.0.0.1` from a
host-network consumer).

## Validation

```sh
cd ../
find liveKitServerAgent -name '*.json' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null
bash -n liveKitServerAgent/scripts/start-livekit-server-agent.sh
bash -n liveKitServerAgent/scripts/hooks/preinstall.sh
```

To build the image locally with Docker:

```sh
docker build \
  -t assistos/livekit-server-agent:webmeet-infra \
  -f ../container-image-builds/images/livekit-server-agent/Dockerfile \
  liveKitServerAgent
```

Use Podman with the same arguments if Podman is the configured runtime.
