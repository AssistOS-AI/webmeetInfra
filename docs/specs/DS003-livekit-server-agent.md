---
id: DS003
title: LiveKit Server Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the LiveKit SFU agent used by WebMeet room media.
---

# DS003 - LiveKit Server Agent

## Introduction

Documents the LiveKit SFU agent used by WebMeet room media.

## Core Content

The `webmeetLivekitServer` agent owns the LiveKit SFU runtime. Its manifest must keep API key and secret values in environment configuration and generated runtime config, not in browser assets or public docs.

LiveKit signaling and media ports are network-sensitive surfaces. Local development may expose them on localhost-style ports, while production review must treat any non-local binding as an operator network-security decision.

`WEBMEET_LIVEKIT_API_KEY` and `WEBMEET_LIVEKIT_API_SECRET` are workspace-owned agent secrets and must be derived from `PLOINKY_DERIVED_MASTER_KEY` through manifest `derive: "derived-master"` entries. These values must use the shared LiveKit derivation identity so `webmeetAgent`, LiveKit server, and egress all agree on the same credentials. Production startup must fail closed only if derived values cannot be produced; no profile may generate `livekit.yaml` with hard-coded development credentials.

The optional `WEBMEET_LIVEKIT_LOG_LEVEL` setting controls the generated LiveKit `logging.level` value and defaults to `info`. Operators may raise it for short diagnostic windows, but generated config and logs must still keep API keys, secrets, tokens, SDP payloads, and credentials out of persisted diagnostics.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

LiveKit Server Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
