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

Startup must require `WEBMEET_TURN_EXTERNAL_IP` and `WEBMEET_TURN_PASSWORD` instead of silently relying on command-line fallbacks. Development profiles may inject local defaults, but production must receive explicit values from Ploinky configuration.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

Coturn Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
