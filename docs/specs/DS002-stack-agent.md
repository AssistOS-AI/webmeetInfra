---
id: DS002
title: Stack Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the stack marker agent that bundles all WebMeet infrastructure dependencies.
---

# DS002 - Stack Agent

## Introduction

Documents the stack marker agent that bundles all WebMeet infrastructure dependencies.

## Core Content

The `stack` agent is a dependency bundle. It must enable Redis, Coturn, LiveKit Server, and LiveKit Egress, and it must provide a lightweight readiness endpoint so Ploinky can model the bundle as a running agent.

The stack agent must not provide WebMeet application APIs or guest surfaces. Starting webmeetAgent may depend on `webmeetInfra/stack`, but stack remains an infrastructure readiness marker.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

Stack Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
