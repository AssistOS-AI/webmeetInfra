# webmeetInfra

Ploinky repository for the WebMeet media runtime.

The runtime is delivered by one Ploinky agent that supervises Redis, Coturn,
LiveKit Server, LiveKit Egress, and (in the `prod` profile) Nginx + Certbot
inside a single container:

- `webmeetInfra/liveKitServerAgent` — see [`liveKitServerAgent/README.md`](liveKitServerAgent/README.md)

The image is published to Docker Hub at
`assistos/livekit-server-agent:webmeet-infra` through the manual
`.github/workflows/publish-livekit-server-agent.yml` workflow. Authentication
uses the `DOCKERHUB_TOKEN` GitHub Actions secret; never commit token values to
the repo.

The app-facing WebMeet agent remains in `AchillesIDE`; this repository only
owns the runtime services.
