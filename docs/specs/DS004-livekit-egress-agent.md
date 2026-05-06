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

Production startup must receive the same `WEBMEET_LIVEKIT_API_KEY` and `WEBMEET_LIVEKIT_API_SECRET` configured for `webmeetLivekitServer`. The production profile must fail closed when those values are missing and must not generate `egress.yaml` with the development `devkey` or `devsecretdevsecretdevsecretdevsecret` fallback.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

LiveKit Egress Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
