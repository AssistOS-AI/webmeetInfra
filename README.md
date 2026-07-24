# webmeetInfra

Ploinky repository for the WebMeet media runtime.

The runtime is delivered by one Ploinky agent that supervises Redis, Coturn,
LiveKit Server, LiveKit Egress, and (in the `prod` profile) Nginx + Certbot
inside a single container:

- `webmeetInfra/liveKitServerAgent` — see [`liveKitServerAgent/README.md`](liveKitServerAgent/README.md)

The manifest pins the reviewed multi-architecture Docker Hub image
`assistos/livekit-server-agent@sha256:012bb28b82300a4e0b720decb6d3b023fc2f26c7a2665832bf1baaeb5b2bb6f9`.
Docker Hub also exposes that image as `webmeet-infra-331fbd1`. It contains the
Redis, Coturn, LiveKit Server, LiveKit Egress, Nginx, Certbot, Node, Python, and
health-check runtime required by this default branch. Future image releases
must be validated against `webmeetInfra/main` and pinned by immutable digest
before deployment.

The app-facing WebMeet agent remains in `AchillesIDE`; this repository only
owns the runtime services.
