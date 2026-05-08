---
id: DS006
title: Redis Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the Redis state service used by LiveKit infrastructure.
---

# DS006 - Redis Agent

## Introduction

Documents the Redis state service used by LiveKit infrastructure.

## Core Content

The `webmeetRedis` agent owns Redis state for the media stack. It is infrastructure state, not an application database for WebMeet room records or guest authorization.

Redis persistence files are runtime data. They must not be used to store application secrets in a way that bypasses webmeetAgent or Ploinky secret handling.

Redis runs on the workspace `webmeet` bridge with the alias `webmeetRedis` and publishes `6379` on the host. Sibling bridge agents (`webmeetLivekitEgress`, future bridge consumers) reach Redis through the bridge alias; host-network agents (`webmeetLivekitServer`) reach Redis through `127.0.0.1:6379` over the published host port. Both consumption paths must remain available because the media stack mixes bridge and host networking by design (see DS003).

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

### Question #2: Why does Redis publish `6379` to the host instead of staying bridge-only?

Response:
LiveKit moved to host networking in DS003, so it can no longer resolve the `webmeetRedis` bridge alias. Publishing `6379` on the host's loopback gives host-network LiveKit a stable address (`127.0.0.1:6379`) without changing the bridge consumption path that egress and other sibling agents use. The published port is bound on `0.0.0.0:6379` for compatibility with podman's port-forwarding model; operators who need to restrict it should bind on `127.0.0.1` only at the manifest level rather than at firewall scope, so the manifest remains the source of truth.

## Conclusion

Redis Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
