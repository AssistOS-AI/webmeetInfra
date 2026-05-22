# webmeetInfra Spec Matrix

This page indexes the local design specification set. The DS files are the source of truth for rules, contracts, and invariants.

## Specification Set

- [DS000 - WebMeet Infra Vision](specsLoader.html?spec=DS000-vision.md)
- [DS001 - Coding Style](specsLoader.html?spec=DS001-coding-style.md)
- [DS002 - liveKitServerAgent](specsLoader.html?spec=DS002-livekit-server-agent.md)
- [DS003 - Ploinky Runtime Invariants](specsLoader.html?spec=DS003-ploinky-runtime-invariants.md)

## Runtime agent

`liveKitServerAgent` is the only Ploinky agent in this repository. Consumers
(`webmeetAgent`, `webmeetLivekitAiAgent`) enable it directly. The Docker image
`assistos/livekit-server-agent:webmeet-infra` is published through the manual
GitHub Actions workflow `publish-livekit-server-agent.yml` using the
`DOCKERHUB_TOKEN` repository secret. The token value is never committed.
