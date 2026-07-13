---
id: DS000
title: WebMeet Infra Vision
status: implemented
owner: webmeet-infra-team
summary: Defines webmeetInfra as the Ploinky media-runtime repository delivered by liveKitServerAgent and turnServerAgent.
---

# DS000 - WebMeet Infra Vision

## Introduction

`webmeetInfra` owns the WebMeet media runtime. The runtime is delivered by two Ploinky agents: `liveKitServerAgent`, which supervises Redis, LiveKit Server, and LiveKit Egress inside one container, and `turnServerAgent`, which runs Coturn as a dedicated TURN/STUN relay using shared-secret REST/ephemeral auth inside its own container. Neither agent runs Nginx or Certbot; the WebMeet signaling edge (TLS termination, reverse proxying) lives in `basic/web-publishing`, a different repository.

## Core Content

`webmeetInfra` must remain an infrastructure repository. It owns media runtime services and generated service configuration; it does not own WebMeet room business logic, guest invite validation, Explorer UI behavior, participant authorization, chat history, transcript storage, AI dispatch policy, or meeting artifact policy. Those contracts belong to `webmeetAgent` and its companion agents.

The active runtime is split across two agents:

| Service | Agent | Responsibility |
| --- | --- | --- |
| Redis | `liveKitServerAgent` | LiveKit node, room, participant, routing, and Egress coordination state. |
| LiveKit Server | `liveKitServerAgent` | SFU media routing, WebSocket signaling, WebRTC negotiation, RTP/RTCP forwarding, data-channel delivery, and Twirp APIs used by `webmeetAgent`. |
| LiveKit Egress | `liveKitServerAgent` | Room composite recording and MP4 writes into the shared recording volume. |
| Coturn | `turnServerAgent` | TURN/STUN relay behavior for WebRTC connectivity, with shared-secret REST/ephemeral auth and a fail-closed peer ACL. |

The `liveKitServerAgent` runtime image is published to Docker Hub as `assistos/livekit-server-agent:webmeet-infra` through the manual `publish-livekit-server-agent.yml` GitHub Actions workflow in `AssistOS-AI/container-image-builds`. Publishing uses the `DOCKERHUB_TOKEN` secret from that repository; token values must never be committed or documented as plaintext. `turnServerAgent` pulls the upstream `docker.io/coturn/coturn` image directly, pinned by digest; it has no custom build or publishing workflow of its own.

Generated LiveKit, Egress, and Redis config belongs under `.data/liveKitServerAgent/generated/`. Coturn config contains the shared TURN secret and is generated only in a private, mode-`0600` in-container runtime directory. Ploinky resolves the shared secret only for host hooks (`runtime: false`); TURN preinstall atomically materializes it at `.ploinky/data/webmeetSecrets/turn/auth-secret` behind a mode-`0700` host parent, and the mode-`0444` leaf is mounted read-only at `/run/webmeet-turn-secret` so Coturn's fixed non-root UID can read it without placing it in OCI environment metadata. Durable infrastructure state belongs under `.ploinky/data/webmeet/...` (LiveKit), `.ploinky/data/webmeetSecrets/turn/` (the confined TURN startup secret), and `.ploinky/data/webmeetTls/turn/` (the TURN agent's production TLS certificate/key, operator- or infrastructure-managed, not agent-generated). Recording files written by Egress are shared file artifacts under `.ploinky/data/webmeet/recordings`; WebMeet recording metadata remains in the `webmeetAgent` encrypted meeting payload.

`webmeetInfra` must not expose guest-facing WebMeet HTTP routes. Public guest access, protected Explorer access, room visibility, recording policy, AI attach/detach policy, and LiveKit participant JWT issuance remain in `webmeetAgent`.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and supervises the media runtime through a manifest and dependency graph just like application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

### Question #2: Why split Coturn out into its own agent instead of keeping the previously consolidated single agent?

Response:
Coturn's auth model changed from static long-term credentials to shared-secret REST/ephemeral auth, and gained a fail-closed peer allow-list and its own production TLS requirement — a genuine security-boundary change, not just a relocation. Splitting it into `turnServerAgent` lets that agent have its own minimal, digest-pinned upstream image (no custom Dockerfile to maintain) and its own readiness contract, independent of LiveKit Server/Egress/Redis's build and health-check needs. The two agents still share exactly one secret (`WEBMEET_TURN_AUTH_SECRET`) via Ploinky's workspace-scoped generated-secret mechanism, so the split does not reintroduce credential duplication.

## Conclusion

`webmeetInfra` remains correct while it owns the media-runtime boundary across `liveKitServerAgent` and `turnServerAgent`, keeps WebMeet application policy outside the infrastructure agents, and preserves generated config, derived secret, recording, and profile topology contracts.
