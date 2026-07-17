---
id: DS000
title: WebMeet Infra Vision
status: implemented
owner: webmeet-infra-team
summary: Defines webmeetInfra as the runtime-v5 LiveKit and Egress service repository with one fixed UDP mux and external relay only.
---

# DS000 - WebMeet Infra Vision

## Introduction

`webmeetInfra` owns the WebMeet media runtime. One Ploinky agent,
`liveKitServerAgent`, supervises Redis, LiveKit Server, LiveKit Egress, and
private health inside a pinned multi-architecture image.

## Core Content

`webmeetInfra` is an infrastructure repository. It owns media runtime services
and generated service configuration; it does not own WebMeet room business
logic, guest invite validation, Explorer UI behavior, participant
authorization, chat history, transcript storage, AI dispatch policy, meeting
artifact policy, Cloudflare publication, or external TURN infrastructure.

The active runtime is the consolidated `liveKitServerAgent`:

| Service | Responsibility |
| --- | --- |
| Redis | Loopback-only LiveKit coordination state. |
| LiveKit Server | Loopback HTTP/WebSocket signaling and Twirp on TCP `7880`, plus the single UDP mux on `7882`. |
| LiveKit Egress | Private template/service traffic on `7980`, semantic health on `7981`, and recording output in the shared recording volume. |
| Supervisor health | A summary readiness listener and detailed supervisor-only health on an unmounted Unix socket. |

LiveKit configuration comes from the immutable, box-owned topology generation.
The advertised node address is the configured literal globally routable
unicast public IPv4,
`use_external_ip` is false, UDP uses exactly `7882`, TCP media is disabled,
and no UDP range is configured. Public WebSocket signaling reaches LiveKit
through the public Router service. Administrative Twirp reaches it only through
the private Router service after authenticated policy and an exact
current-generation caller assertion.

TURN is external. Ploinky core brokers short-lived credentials to exact allowed
consumers. No long-term TURN secret, local relay, public TLS proxy, certificate
process, tunnel connector, DNS automation, or physical-host publication field
belongs in this repository.

Generated runtime config belongs under `.data/liveKitServerAgent/generated/`.
Durable Redis and recording state belongs under `.ploinky/data/webmeet/`.
Recording metadata remains in the `webmeetAgent` encrypted meeting payload.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and supervises the media runtime through a manifest and immutable
dependency generation. Keeping the service contract in a DS file preserves the
runtime, listener, secret, and dependency assumptions for future changes.

### Question #2: Why consolidate these media processes into one agent?

Response:
LiveKit Server, Egress, Redis, and health need matching generated configuration,
shared derived credentials, deterministic startup order, and one semantic
readiness boundary. Consolidation lets readiness represent the usable media
runtime without granting the agent ownership of Router publication or relay
infrastructure.

## Conclusion

`webmeetInfra` remains correct while it owns only the private media-runtime
boundary, keeps application policy and edge publication outside the agent, and
preserves the fixed UDP mux, generated configuration, and recording contracts.
