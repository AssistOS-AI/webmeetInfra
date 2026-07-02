---
id: DS000
title: WebMeet Infra Vision
status: implemented
owner: webmeet-infra-team
summary: Defines webmeetInfra as the Ploinky media-runtime repository delivered by the consolidated liveKitServerAgent.
---

# DS000 - WebMeet Infra Vision

## Introduction

`webmeetInfra` owns the WebMeet media runtime. The runtime is delivered by one Ploinky agent, `liveKitServerAgent`, which supervises Redis, Coturn, LiveKit Server, LiveKit Egress, and, in the `prod` profile, Nginx plus a Certbot renewal loop inside one container.

## Core Content

`webmeetInfra` must remain an infrastructure repository. It owns media runtime services and generated service configuration; it does not own WebMeet room business logic, guest invite validation, Explorer UI behavior, participant authorization, chat history, transcript storage, AI dispatch policy, or meeting artifact policy. Those contracts belong to `webmeetAgent` and its companion agents.

The active runtime is the consolidated `liveKitServerAgent`:

| Service | Responsibility |
| --- | --- |
| Redis | LiveKit node, room, participant, routing, and Egress coordination state. |
| Coturn | TURN/STUN relay behavior for WebRTC connectivity. |
| LiveKit Server | SFU media routing, WebSocket signaling, WebRTC negotiation, RTP/RTCP forwarding, data-channel delivery, and Twirp APIs used by `webmeetAgent`. |
| LiveKit Egress | Room composite recording and MP4 writes into the shared recording volume. |
| Nginx and Certbot | Production-only TLS termination and certificate renewal for the LiveKit signaling hostname. |

The runtime image is published to Docker Hub as `assistos/livekit-server-agent:webmeet-infra` through the manual `publish-livekit-server-agent.yml` GitHub Actions workflow in `AssistOS-AI/container-image-builds`. Publishing uses the `DOCKERHUB_TOKEN` secret from that repository; token values must never be committed or documented as plaintext.

Generated runtime config belongs under `.data/liveKitServerAgent/generated/`. Durable infrastructure state belongs under `.ploinky/data/webmeet/...` and `.ploinky/data/webmeetTls/...`. Recording files written by Egress are shared file artifacts under `.ploinky/data/webmeet/recordings`; WebMeet recording metadata remains in the `webmeetAgent` encrypted meeting payload.

`webmeetInfra` must not expose guest-facing WebMeet HTTP routes. Public guest access, protected Explorer access, room visibility, recording policy, AI attach/detach policy, and LiveKit participant JWT issuance remain in `webmeetAgent`.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and supervises the media runtime through a manifest and dependency graph just like application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

### Question #2: Why consolidate media infrastructure into one agent?

Response:
LiveKit Server, Egress, Redis, Coturn, and production TLS need matching generated configuration, shared derived credentials, and an ordering-aware health gate. One consolidated agent makes Ploinky readiness represent the usable media runtime instead of only one member of a split service graph.

## Conclusion

`webmeetInfra` remains correct while it owns the consolidated media-runtime boundary, keeps WebMeet application policy outside the infrastructure agent, and preserves generated config, derived secret, recording, and profile topology contracts.
