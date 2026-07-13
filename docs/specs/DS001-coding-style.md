---
id: DS001
title: Coding Style
status: implemented
owner: webmeet-infra-team
summary: Defines documentation, manifest, hook, and validation style for webmeetInfra.
---

# DS001 - Coding Style

## Introduction

This specification is the local coding-style authority for `webmeetInfra`. It covers the consolidated LiveKit runtime repository: manifests, centralized Docker image source contracts, generated config hooks, shell supervision, health checks, and documentation.

## Core Content

`webmeetInfra` changes are mostly manifests, generated runtime config templates, shell scripts, centralized Docker image source contracts, and documentation. JSON manifests use two-space indentation where the local file already does so. Shell hooks and supervisors should use portable POSIX shell patterns unless a manifest explicitly chooses another shell. Documentation, specifications, and code comments must be written in English.

The local source layout is contract-bearing:

| Path | Purpose |
| --- | --- |
| `liveKitServerAgent/manifest.json` | Ploinky start-only command, network profile, ports, volumes, readiness, and derived secret contract. |
| `AssistOS-AI/container-image-builds/images/livekit-server-agent/Dockerfile` | Central runtime image definition that installs Redis, LiveKit Server, LiveKit Egress, Node, and Ploinky dependency-cache tools against this repository's `liveKitServerAgent` build context. |
| `liveKitServerAgent/scripts/hooks/preinstall.sh` | Generates runtime config under `.data/liveKitServerAgent/generated/`. |
| `liveKitServerAgent/scripts/start-livekit-server-agent.sh` | Supervises the in-container services and readiness gate. |
| `liveKitServerAgent/readiness.sh` | Root-level Ploinky readiness probe (TCP reachability of Redis/LiveKit/Egress). |
| `AssistOS-AI/container-image-builds/.github/workflows/publish-livekit-server-agent.yml` | Manual Docker image publishing workflow. |
| `turnServerAgent/manifest.json` | Ploinky start-only command, network profile, ports, volumes, readiness, and derived secret contract for the dedicated Coturn TURN relay (pulls the upstream image directly, pinned by digest; no custom Dockerfile). |
| `turnServerAgent/scripts/hooks/preinstall.sh` | Validates quota, canonical peer, external-address, and production TLS inputs on the host. |
| `turnServerAgent/scripts/start-turn-server-agent.sh` | Generates a private in-container `turnserver.conf` and executes `turnserver`. |
| `turnServerAgent/readiness.sh` | Root-level Ploinky readiness probe (process/listener/IPv6/TLS checks plus a no-secret STUN Binding request; relay-only browser E2E proves authenticated TURN allocation). |
| `docs/specs/` | Authoritative DS contracts. |

Generated or runtime-owned files such as LiveKit YAML, Egress YAML, Redis data, TLS material, and recording outputs must not be treated as hand-authored source files. Generated config templates must use manifest-provided env and derived secrets; they must not commit plaintext local credentials.

Validation should start with the narrowest check that covers the edited surface:

- `find . -name '*.json' -not -path './.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null`
- `bash -n liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `bash -n liveKitServerAgent/scripts/hooks/preinstall.sh`
- `bash -n liveKitServerAgent/readiness.sh`
- `bash -n turnServerAgent/scripts/start-turn-server-agent.sh`
- `bash -n turnServerAgent/scripts/hooks/preinstall.sh`
- `bash -n turnServerAgent/readiness.sh`
- `node --test tests/unit/*.test.mjs`

Runtime topology changes require a Ploinky smoke path such as `ploinky start AchillesIDE/webmeetAgent` followed by `ploinky status`, or a clear note explaining why that runtime check was not run.

## Decisions & Questions

### Question #1: Why make generated config rules part of coding style?

Response:
The generated config hook is where profile env, derived secrets, internal URLs, ports, recording paths, and production TLS settings become runtime files. Treating those files as generated output prevents stale checked-in YAML or local secrets from becoming a second source of truth.

### Question #2: Why validate shell scripts even for documentation-only topology changes?

Response:
The shell scripts encode the readiness and process-supervision contract. Documentation that changes service order, profile URL patterns, or generated config paths can become wrong quickly if the scripts drift. Syntax validation is cheap and catches accidental breakage before a runtime smoke test.

## Conclusion

Coding Style remains valid while infrastructure changes preserve the local source layout, centralized image-build boundary, generated-config boundary, derived-secret behavior, shell validation expectations, and DS/documentation synchronization rules.
