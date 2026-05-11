---
id: DS005
title: Coturn Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the TURN/STUN service used for WebMeet connectivity.
---

# DS005 - Coturn Agent

## Introduction

Documents the TURN/STUN service used for WebMeet connectivity.

## Core Content

The `webmeetCoturn` agent owns TURN/STUN connectivity for WebMeet clients. Credentials, realm, external IP, and relay port range are runtime configuration, not application policy.

Production operators must review relay port exposure and external IP configuration before exposing the service beyond a local development host.

Startup must require a concrete TURN external address and `WEBMEET_TURN_PASSWORD` instead of silently relying on command-line fallbacks. `WEBMEET_TURN_PASSWORD` is a workspace-owned agent secret and must be derived from `PLOINKY_DERIVED_MASTER_KEY` through manifest `derive: "derived-master"` entries using the shared TURN derivation identity. Deployment topology values are non-sensitive profile config without hard-coded public IPs: the production profile uses `WEBMEET_TURN_EXTERNAL_IP=auto` plus `WEBMEET_TURN_HOST=livekit-skills.axiologic.dev`, and the coturn start command resolves that hostname to the IP passed to `turnserver --external-ip`. Operators may override `WEBMEET_TURN_EXTERNAL_IP` through Ploinky vars when DNS-based resolution is unsuitable.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

Coturn Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
