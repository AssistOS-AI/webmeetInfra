# webmeetInfra Agent Guide

## Scope

webmeetInfra is a standalone Ploinky repo for the WebMeet media runtime. It
ships a single agent, `liveKitServerAgent`, which supervises Redis, LiveKit
Server, LiveKit Egress, and private health inside a pinned image. TURN is
external; Router publication and Cloudflare/DNS state are box-owned.

## Mandatory Reading Order

1. Read the nearest parent `AGENTS.md` for workspace-wide rules.
2. Read `docs/index.html` for the local documentation entry point.
3. Read `docs/specs/matrix.md` and the relevant local DS files before changing behavior.
4. Read `docs/specs/DS003-ploinky-runtime-invariants.md` before touching auth, routing, guest access, MCP, HTTP services, files, logs, or runtime configuration.
5. Read `docs/specs/DS002-livekit-server-agent.md` for the `liveKitServerAgent` contract.
6. Read `docs/specs/DS001-coding-style.md` for coding style, module structure, and test-organization rules when that file exists; otherwise inherit the parent repository coding-style authority.

## Current Skill Catalog

- No local skill catalog is declared for this agent.

## Repository Rules

- The DS specifications are the source of truth for local contracts and invariants.
- When source code changes behavior, interfaces, architecture, workflows, security boundaries, or runtime configuration, update both the HTML documentation and the DS specifications.
- Keep DS numbering gap-free within any newly initialized GAMP spec set. Preserve existing local numbering conventions unless a migration updates all links in the same change.
- All documentation, specifications, and code comments must be written in English.
- Do not add imported-skill DS files or skill pages to a downstream host project's docs tree.
- Keep Ploinky runtime invariants in local context: router-mediated entry, secure-wire invocation JWTs, scoped guest mode, manifest-declared HTTP services, workspace-confined paths, and redacted logs.
- Never add AI/coding-agent attribution to commits, release notes, changelogs, generated metadata, comments, or documentation.
- Update `AGENTS.md` and `CLAUDE.md` together so coding agents receive the same local context.

## Runtime Defaults

Infrastructure runs as a single Ploinky agent started by consumers
(`webmeetAgent`, `webmeetLivekitAiAgent`). It owns media/runtime services only
and must not implement application guest policy. The supervisor starts Redis,
LiveKit Server, LiveKit Egress, and health in order. Detailed health is
supervisor-only on `/run/ploinky/livekit-supervisor.sock`; the managed summary
readiness listener exposes no administration surface.

Generated configuration requires the immutable box-owned topology generation.
LiveKit HTTP/Twirp binds loopback TCP `7880`; public signaling and private
administration use their declared Router services. LiveKit alone owns UDP
`7882`. Do not add local TURN, TLS termination, certificate automation, tunnel
connectors, or manifest-driven physical publications.

The supervisor must not try to launch sibling Ploinky agents. Manifest `enable`
edges are resolved by Ploinky before the container exists; an in-container
process has no view of the host runtime and cannot spawn additional agents.

## Key Paths

- `docs/specs/matrix.md`
- `liveKitServerAgent/manifest.json`
- `liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `liveKitServerAgent/scripts/hooks/preinstall.sh`
- `liveKitServerAgent/scripts/health/livekit-server-agent-health.sh`
- `liveKitServerAgent/scripts/health/supervisor-health.mjs`

## Validation

Run the narrowest relevant check after edits, then broaden when touching shared behavior:

- `find . -name '*.json' -not -path './.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null`
- `sh -n liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `sh -n liveKitServerAgent/scripts/hooks/preinstall.sh`
- `sh -n liveKitServerAgent/scripts/health/livekit-server-agent-health.sh`
- `node --check liveKitServerAgent/scripts/health/supervisor-health.mjs`
- `ploinky start AchillesIDE/webmeetAgent`
- `ploinky status`
