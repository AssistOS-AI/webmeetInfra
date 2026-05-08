---
id: DS004
title: LiveKit Egress Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the LiveKit egress worker and recording storage boundary.
---

# DS004 - LiveKit Egress Agent

## Introduction

Documents the LiveKit egress worker and recording storage boundary.

## Core Content

The `webmeetLivekitEgress` agent owns recording and egress worker execution. It may receive generated egress config and write recordings only to the declared recording volume.

Egress must not become a general host command runner. Capability grants such as `SYS_ADMIN` are manifest-level trust decisions and must stay documented because they widen the runtime trust boundary.

Production startup must receive the same `WEBMEET_LIVEKIT_API_KEY` and `WEBMEET_LIVEKIT_API_SECRET` derived for `webmeetLivekitServer`. Those values are workspace-owned agent secrets and must be derived from `PLOINKY_DERIVED_MASTER_KEY` through manifest `derive: "derived-master"` entries using the shared LiveKit derivation identity; no profile may generate `egress.yaml` with hard-coded development credentials.

The egress worker remains on the workspace `webmeet` bridge, but `webmeetLivekitServer` runs on host networking, so the bridge alias `webmeetLivekitServer:7880` is no longer resolvable. Egress reaches LiveKit through the host gateway entry the runtime exposes for bridge agents (`host.containers.internal` on podman with netavark, or the bridge gateway IP). The `WEBMEET_LIVEKIT_INTERNAL_WS_URL` setting controls the `ws_url` value written into `egress.yaml`; the generated default is `ws://host.containers.internal:7880`, except in the `dev` profile where it is `ws://host.containers.internal:17880` to match the profile-specific host-network LiveKit signaling port. The optional `WEBMEET_EGRESS_REDIS_ADDRESS` setting (default `webmeetRedis:6379`) controls the `redis.address` value; egress is still on the bridge and the Redis bridge alias still resolves there.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

### Question #2: Why does egress reach LiveKit through `host.containers.internal` instead of a bridge alias?

Response:
LiveKit moved to `network.mode: "host"` to fix the podman bridge UDP src-NAT issue described in DS003. Once LiveKit leaves the `webmeet` bridge, the `webmeetLivekitServer` DNS alias the egress agent previously used no longer resolves. Sibling agents that stay on the bridge reach a host-network agent through the runtime's host gateway entry (`host.containers.internal` or the bridge gateway IP). Making the URL configurable via `WEBMEET_LIVEKIT_INTERNAL_WS_URL` keeps the manifest portable across topologies (host-net LiveKit in production, bridge LiveKit in some test setups) without forking the egress preinstall.

## Conclusion

LiveKit Egress Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
