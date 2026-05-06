---
id: DS000
title: WebMeet Infra Vision
status: implemented
owner: webmeet-infra-team
summary: Defines webmeetInfra as a Ploinky repository of reusable media infrastructure agents for WebMeet.
---

# DS000 - WebMeet Infra Vision

## Introduction

Defines webmeetInfra as a Ploinky repository of reusable media infrastructure agents for WebMeet.

## Core Content

webmeetInfra exists to keep WebMeet media infrastructure separate from the application-facing WebMeet agent. The repository owns Redis, TURN/STUN, LiveKit server, LiveKit egress, and a stack dependency bundle so Ploinky can start the media stack through normal agent dependency resolution.

The repository must remain an infrastructure repository. It must not own WebMeet room business logic, guest invite validation, Explorer UI behavior, or meeting artifact policy. Those contracts belong to webmeetAgent.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

WebMeet Infra Vision remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
