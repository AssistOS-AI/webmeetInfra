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
assistos/livekit-server-agent:webmeet-infra
```

The manifest references the image through `${WEBMEET_INFRA_IMAGE_TAG}` so
operators can override the tag through `ploinky var WEBMEET_INFRA_IMAGE_TAG=…`
without editing the manifest.

The image is published through `.github/workflows/publish-livekit-server-agent.yml`
(manual `workflow_dispatch` only). It uses the `DOCKERHUB_TOKEN` repository
secret and publishes `linux/amd64` plus `linux/arm64` variants. Do not store
the token in this repo.

## Files

- `manifest.json` — Ploinky manifest with `default`, `dev`, and `prod` profiles
- `Dockerfile` — final image based on `livekit/egress` plus `livekit-server`,
  `redis-server`, `coturn`, `nginx`, `certbot`, `tini`, and `curl`
- `scripts/start-livekit-server-agent.sh` — in-container supervisor
- `scripts/hooks/preinstall.sh` — host-side generator for runtime config
- `scripts/health/livekit-server-agent-health.sh` — operator smoke check

## Profiles

| Profile | Network                  | Health port (host) | LiveKit signaling | Consumer URL pattern                                |
|---------|--------------------------|--------------------|-------------------|-----------------------------------------------------|
| default | bridge `webmeet`         | 127.0.0.1:17000    | 127.0.0.1:7880    | `http://liveKitServerAgent:7880`, `:7980`           |
| dev     | bridge `webmeet`         | 127.0.0.1:17000    | 127.0.0.1:17880   | `http://liveKitServerAgent:17880`, `:7980`          |
| prod    | host networking          | 127.0.0.1:17000    | 0.0.0.0:7880      | `http://host.containers.internal:7880`/`:7980`      |

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
docker build -t assistos/livekit-server-agent:webmeet-infra liveKitServerAgent
```

Use Podman with the same arguments if Podman is the configured runtime.
