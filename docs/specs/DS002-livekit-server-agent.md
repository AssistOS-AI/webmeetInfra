---
id: DS002
title: liveKitServerAgent
status: implemented
owner: webmeet-infra-team
summary: Supervises the pinned v5 Redis, LiveKit, Egress, and private health runtime with one fixed UDP mux.
---

# DS002 - liveKitServerAgent

## Introduction

`liveKitServerAgent` owns the fixed runtime-v5 LiveKit, Egress, Redis, and
private-health process boundary. It consumes immutable box topology and never
discovers or substitutes a media address.

## Core Content

### Image and process model

The manifest uses a pinned multi-architecture image digest for every profile.
One supervisor starts Redis, LiveKit Server, LiveKit Egress, and a compact
health process. It traps termination, shuts children down, and fails if a
required process or expected socket owner disappears.

Detailed health is available only on the unmounted Unix socket
`/run/ploinky/livekit-supervisor.sock`. A loopback summary listener exists for
the managed readiness probe and exposes no administration surface.

### Generated configuration

The preinstall hook reads the mounted schema-v2 topology and requires:

- a canonical literal globally routable unicast `media.publicIPv4`;
- media UDP port `7882`; and
- `direct` or `nat-forward` address mode.

It generates LiveKit with HTTP/signaling on `127.0.0.1:7880`,
`rtc.node_ip` equal to the validated globally routable unicast IPv4,
`use_external_ip: false`, one
UDP mux on `7882`, and TCP media disabled. Redis binds `127.0.0.1:6379`.
Egress template/service binds loopback `7980` and semantic health binds
loopback `7981`; readiness proves both roles independently by requiring the
`egress` socket owner, rejecting any non-loopback duplicate, validating the
health JSON `CpuLoad`, and validating the pinned LiveKit Egress HTML template.
The upstream v1.9.1 binary binds health to wildcard, so the runtime accepts only
the separate commit-pinned rebuild whose narrow source patch changes that bind
to `127.0.0.1`. Startup fails closed with the upstream binary.

No local relay, UDP range, public TLS proxy, or certificate process is part of
this image. Startup rejects unexpected wildcard/control listeners and verifies
that LiveKit owns UDP `7882`.

### Manifest and Router

Every profile resolves to exact host mode under Ploinky's current-generation
capability. The manifest declares public `livekit-signal` and authenticated
private `livekit-api` services, both targeting loopback TCP `7880`. It declares
no physical publications. Public signaling uses Router `8080`; Twirp uses the
private Router listener and requires both authenticated policy and an exact
caller assertion.

The outer box always reserves UDP `7882`, independent of whether this agent is
enabled. Only one granted current generation may bind it. A conflict or wrong
socket owner is an actionable startup failure.

### External relay

TURN is an external service described by non-secret topology. Ploinky core
brokers short-lived credentials to exact authorized consumers; this agent does
not receive the long-term relay secret and does not supervise a relay process.

## Decisions & Questions

### Question #1: Why reject syntactically valid non-global IPv4 addresses?

Response:
LiveKit advertises `rtc.node_ip` directly to remote peers, so private,
loopback, link-local, CGNAT, documentation, benchmark, multicast, reserved, and
other special-purpose ranges cannot satisfy the cross-network direct-UDP
contract. Configuration generation therefore accepts only canonical literal
global-unicast IPv4 input and fails closed without address discovery or a
fallback candidate.

## Verification

Unit and integration checks validate topology parsing, fixed config, socket
ownership, service/readiness semantics, and forbidden listeners. Release gates
run direct UDP on native Linux x64 and arm64 with two browsers on distinct
external networks, plus external relay UDP and TLS fallback lanes.

Publication of the patched multi-architecture Egress image and repinning the
liveKitServerAgent base to its returned manifest digest are mandatory release
prerequisites; a local architecture build is not a substitute for that digest.

## Conclusion

The agent is valid only when immutable topology supplies a canonical literal
globally routable unicast IPv4, LiveKit alone owns UDP `7882`, and all signaling,
administration, Egress, health, and relay boundaries remain private or
Router-mediated as specified above.
