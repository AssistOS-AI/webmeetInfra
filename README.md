# webmeetInfra

Ploinky repository for the WebMeet media runtime.

The runtime is delivered by two Ploinky agents:

- `webmeetInfra/liveKitServerAgent` — supervises Redis, LiveKit Server, and
  LiveKit Egress inside one container; see
  [`liveKitServerAgent/README.md`](liveKitServerAgent/README.md)
- `webmeetInfra/turnServerAgent` — runs Coturn as a dedicated TURN/STUN relay
  with shared-secret REST/ephemeral auth and a fail-closed peer ACL; see
  [`turnServerAgent/README.md`](turnServerAgent/README.md)

Neither agent runs Nginx or Certbot. The WebMeet signaling edge (TLS
termination, reverse proxying) lives in `basic/web-publishing`, a different
repository.

The `liveKitServerAgent` image is published to Docker Hub at
`assistos/livekit-server-agent:webmeet-infra` through the manual
`publish-livekit-server-agent.yml` workflow in
`AssistOS-AI/container-image-builds`. That workflow checks out this repository
as the build context, uses the centralized Dockerfile from
`container-image-builds/images/livekit-server-agent/Dockerfile`, and publishes
`linux/amd64` and `linux/arm64` variants under the same tag. It also exposes and
validates the pushed manifest digest, then reports the immutable image reference
in the workflow log and summary. The consumer manifest is pinned separately to
`sha256:e8aee1f63763a3dcb427f47d3e0aab78b7932a8c1d6140fce43f7bde960b47f8`.
Authentication
uses the `DOCKERHUB_TOKEN` GitHub Actions secret in
`AssistOS-AI/container-image-builds`; never commit token values to any repo.
`turnServerAgent` pulls the upstream `docker.io/coturn/coturn` image directly,
pinned by digest; it has no custom build or publishing workflow.

The app-facing WebMeet agent remains in `AchillesIDE`; this repository only
owns the runtime services.
