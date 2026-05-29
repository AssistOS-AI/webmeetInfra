# webmeetInfra

Ploinky repository for the WebMeet media runtime.

The runtime is delivered by one Ploinky agent that supervises Redis, Coturn,
LiveKit Server, LiveKit Egress, and (in the `prod` profile) Nginx + Certbot
inside a single container:

- `webmeetInfra/liveKitServerAgent` — see [`liveKitServerAgent/README.md`](liveKitServerAgent/README.md)

The image is published to Docker Hub at
`assistos/livekit-server-agent:webmeet-infra` through the manual
`publish-livekit-server-agent.yml` workflow in
`AssistOS-AI/container-image-builds`. That workflow checks out this repository
as the build context, uses the centralized Dockerfile from
`container-image-builds/images/livekit-server-agent/Dockerfile`, and publishes
`linux/amd64` and `linux/arm64` variants under the same tag. Authentication
uses the `DOCKERHUB_TOKEN` GitHub Actions secret in
`AssistOS-AI/container-image-builds`; never commit token values to any repo.

The app-facing WebMeet agent remains in `AchillesIDE`; this repository only
owns the runtime services.
