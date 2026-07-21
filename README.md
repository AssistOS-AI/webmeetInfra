# webmeetInfra

Ploinky repository for the WebMeet media runtime.

The runtime is delivered by one Ploinky agent that supervises Redis, Coturn,
LiveKit Server, LiveKit Egress, and (in the `prod` profile) Nginx + Certbot
inside a single container:

- `webmeetInfra/liveKitServerAgent` — see [`liveKitServerAgent/README.md`](liveKitServerAgent/README.md)

The manifest pins the bridge-compatible multi-architecture image index
`docker.io/assistos/livekit-server-agent@sha256:012bb28b82300a4e0b720decb6d3b023fc2f26c7a2665832bf1baaeb5b2bb6f9`,
originally published as `webmeet-infra-331fbd1`. It does not use the mutable
`webmeet-infra` tag. Images are published through the manual
`publish-livekit-server-agent.yml` workflow in
`AssistOS-AI/container-image-builds`. That workflow checks out this repository
as the build context, uses the centralized Dockerfile from
`container-image-builds/images/livekit-server-agent/Dockerfile`, and publishes
`linux/amd64` and `linux/arm64` variants under the same tag. Authentication
uses the `DOCKERHUB_TOKEN` GitHub Actions secret in
`AssistOS-AI/container-image-builds`; never commit token values to any repo.

The app-facing WebMeet agent remains in `AchillesIDE`; this repository only
owns the runtime services.
