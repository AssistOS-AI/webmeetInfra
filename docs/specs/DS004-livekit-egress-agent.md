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

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

LiveKit Egress Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
