---
id: DS001
title: Coding Style
status: implemented
owner: webmeet-infra-team
summary: Defines documentation, manifest, generated-config, supervision, and validation style for runtime-v5 webmeetInfra.
---

# DS001 - Coding Style

## Introduction

This specification is the local coding-style authority for `webmeetInfra`. It
covers the LiveKit runtime manifest, pinned image contract, topology-driven
configuration hook, shell supervision, private health implementation, tests,
and documentation.

## Core Content

JSON manifests use two-space indentation where the local file already does so.
Shell hooks and supervisors use portable POSIX shell patterns unless a manifest
explicitly selects another shell. JavaScript health helpers use ESM. All
documentation, specifications, and code comments are written in English.

The local source layout is contract-bearing:

| Path | Purpose |
| --- | --- |
| `liveKitServerAgent/manifest.json` | Pinned image, exact host-mode capability, Router services, private volumes, readiness, and derived-secret contract. |
| `liveKitServerAgent/scripts/hooks/preinstall.sh` | Validates the mounted topology generation and generates fixed LiveKit, Redis, and Egress configuration. |
| `liveKitServerAgent/scripts/start-livekit-server-agent.sh` | Supervises required processes, enforces socket ownership, and fails closed. |
| `liveKitServerAgent/scripts/health/livekit-server-agent-health.sh` | Summary readiness probe used by the managed runtime. |
| `liveKitServerAgent/scripts/health/supervisor-health.mjs` | Detailed supervisor-only health served on the unmounted Unix socket. |
| `docs/specs/` | Authoritative DS contracts. |

Generated LiveKit, Redis, and Egress files are runtime output, not hand-authored
source. They must use the mounted immutable topology and manifest-provided
derived secrets. They must not persist topology candidates, caller assertions,
long-term relay credentials, or plaintext operator credentials.

The manifest remains slim. It may declare normal `httpServices` targets and
agent dependencies, but it must not contain physical publication, UDP, edge,
Cloudflare, topology, or generic server-inventory sections. The runtime does
not start a local TURN daemon, TLS proxy, certificate process, or tunnel
connector.

Validation starts with the narrowest checks that cover the edited surface:

- `find . -name '*.json' -not -path './.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null`
- `sh -n liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `sh -n liveKitServerAgent/scripts/hooks/preinstall.sh`
- `sh -n liveKitServerAgent/scripts/health/livekit-server-agent-health.sh`
- `node --check liveKitServerAgent/scripts/health/supervisor-health.mjs`

Runtime-topology changes also require the native Linux release lanes: direct
UDP on amd64 and arm64 with two browsers on distinct external networks, plus
external TURN/UDP and TURN/TLS fallback. If those prerequisites are not
available locally, record the exact blocked gate instead of weakening it.

## Decisions & Questions

### Question #1: Why make generated config rules part of coding style?

Response:
The preinstall hook is where the immutable topology and derived secrets become
runtime files. Treating these files as generated output prevents stale YAML,
candidate topology, or local credentials from becoming a second source of
truth.

### Question #2: Why validate listener ownership as well as shell syntax?

Response:
Syntax checks prove only that scripts parse. The security and publication
boundary also requires LiveKit to own UDP `7882`, administrative services to
remain private, and unexpected wildcard/control listeners to fail startup.

## Conclusion

Coding Style remains valid while changes preserve the pinned image boundary,
immutable topology input, generated-config boundary, exact listener ownership,
shell and ESM validation, release-gate expectations, and synchronized DS/HTML
documentation.
