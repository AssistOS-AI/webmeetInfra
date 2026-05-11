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

The egress worker remains on the workspace `webmeet` bridge. Its LiveKit control URL must match the active LiveKit topology: the `default` profile uses `ws://webmeetLivekitServer:7880`, the `dev` profile uses `ws://webmeetLivekitServer:17880`, and the `prod` profile uses `ws://host.containers.internal:7880` because production LiveKit runs with `network.mode: "host"` and does not register the bridge alias. The `WEBMEET_LIVEKIT_INTERNAL_WS_URL` setting controls the `ws_url` value written into `egress.yaml` and remains operator-overridable. The optional `WEBMEET_EGRESS_REDIS_ADDRESS` setting (default `webmeetRedis:6379`) controls the `redis.address` value; egress is still on the bridge and the Redis bridge alias still resolves there.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

### Question #2: Why is egress's LiveKit URL profile-specific?

Response:
LiveKit uses different network namespaces by profile. Production keeps `network.mode: "host"` to avoid the podman bridge UDP src-NAT issue described in DS003, so sibling bridge agents must reach LiveKit through the runtime's host gateway entry (`host.containers.internal` or the bridge gateway IP). The `default` and `dev` profiles deliberately keep LiveKit on the shared `webmeet` bridge so developer workstations can satisfy readiness probes and sibling agents can reach LiveKit through `webmeetLivekitServer`; `dev` binds signaling on `17880`, so egress must use that port. Making the URL configurable via `WEBMEET_LIVEKIT_INTERNAL_WS_URL` keeps the manifest portable without forking the egress preinstall.

## Conclusion

LiveKit Egress Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
