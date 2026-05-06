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

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

Redis Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
