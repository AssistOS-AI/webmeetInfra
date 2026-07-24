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
assistos/livekit-server-agent@sha256:012bb28b82300a4e0b720decb6d3b023fc2f26c7a2665832bf1baaeb5b2bb6f9
```

The manifest pulls this immutable multi-architecture digest for every profile.
Docker Hub also exposes it as `webmeet-infra-331fbd1`. Its required binaries
and bundled supervisor/health scripts have been verified against
`webmeetInfra/main`. Do not replace the digest with the mutable
`webmeet-infra` tag: that channel may target a different branch contract.

## Files

- `manifest.json` — Ploinky manifest with `default`, `dev`, and `prod` profiles
- pinned runtime image — based on `livekit/egress` plus `livekit-server`, Node,
  `redis-server`, `coturn`, `nginx`, `certbot`, `python3`, `tini`, `curl`, and
  Ploinky dependency-cache tools (`git`, `make`, `g++`)
- `scripts/start-livekit-server-agent.sh` — in-container supervisor
- `scripts/hooks/preinstall.sh` — host-side generator for runtime config
- `scripts/health/livekit-server-agent-health.sh` — operator smoke check

## Profiles

| Profile | Network                  | Health port (host) | LiveKit signaling | Consumer URL pattern                                |
|---------|--------------------------|--------------------|-------------------|-----------------------------------------------------|
| default | bridge `webmeet`         | 127.0.0.1:17000    | 0.0.0.0:7880      | `http://liveKitServerAgent:7880`, `:7980`           |
| dev     | bridge `webmeet`         | 127.0.0.1:17000    | 0.0.0.0:17880     | `http://liveKitServerAgent:17880`, `:7980`          |
| prod    | host networking          | 127.0.0.1:17000    | 0.0.0.0:7880      | `http://host.containers.internal:7880`/`:7980`      |

Default and dev generated LiveKit config advertise the detected workstation
IPv4 address as the SFU ICE node address unless `WEBMEET_LIVEKIT_NODE_IP` is
explicitly set. `WEBMEET_LOCAL_PUBLIC_HOST` overrides detection. Browser-facing
LiveKit media and TURN ports are intentionally LAN-published in these local
profiles because Firefox on macOS/Podman does not reliably connect through
loopback-only ICE candidates.

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

Before pinning a replacement image, verify both supported architectures, every
required binary listed above, the supervisor and health-script checksums, and a
full Ploinky startup using this repository's current `main` branch.
