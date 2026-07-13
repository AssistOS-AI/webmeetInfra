# webmeetInfra Agent Guide

## Scope

webmeetInfra is a standalone Ploinky repo for the WebMeet media runtime. It
ships two agents: `liveKitServerAgent`, which supervises Redis, LiveKit
Server, and LiveKit Egress inside one container, and `turnServerAgent`, which
runs Coturn as a dedicated TURN/STUN relay with shared-secret REST/ephemeral
auth. Neither agent runs Nginx or Certbot; the WebMeet signaling edge lives in
`basic/web-publishing`, a different repository.

## Mandatory Reading Order

1. Read the nearest parent `AGENTS.md` for workspace-wide rules.
2. Read `docs/index.html` for the local documentation entry point.
3. Read `docs/specs/matrix.md` and the relevant local DS files before changing behavior.
4. Read `docs/specs/DS003-ploinky-runtime-invariants.md` before touching auth, routing, guest access, MCP, HTTP services, files, logs, or runtime configuration.
5. Read `docs/specs/DS002-livekit-server-agent.md` for the `liveKitServerAgent` contract.
6. Read `docs/specs/DS004-turn-server-agent.md` for the `turnServerAgent` contract (shared secret, peer ACL, production TLS).
7. Read `docs/specs/DS001-coding-style.md` for coding style, module structure, and test-organization rules when that file exists; otherwise inherit the parent repository coding-style authority.

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

Infrastructure runs as two Ploinky agents started by consumers
(`webmeetAgent`, `webmeetLivekitAiAgent`). Both own media/runtime services only
and must not implement application guest policy. `liveKitServerAgent`'s
supervisor starts Redis → LiveKit Server → LiveKit Egress in order;
`turnServerAgent`'s supervisor starts only `turnserver`. Neither publishes a
health port anymore; both use a manifest `start` command and declare
`health.readiness.script` (a root-level `readiness.sh` in each agent
directory) instead of an MCP `agent` command or `readiness.protocol`.

Neither supervisor may try to launch sibling Ploinky agents. Manifest `enable`
edges are resolved by Ploinky before the container exists; an in-container
process has no view of the host runtime and cannot spawn additional agents.

## Key Paths

- `docs/specs/matrix.md`
- `liveKitServerAgent/manifest.json`
- `../container-image-builds/images/livekit-server-agent/Dockerfile` — centralized image definition for the `liveKitServerAgent` build context
- `liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `liveKitServerAgent/scripts/hooks/preinstall.sh`
- `liveKitServerAgent/readiness.sh`
- `../container-image-builds/.github/workflows/publish-livekit-server-agent.yml` — centralized Docker Hub publish workflow
- `turnServerAgent/manifest.json`
- `turnServerAgent/scripts/start-turn-server-agent.sh`
- `turnServerAgent/scripts/hooks/preinstall.sh`
- `turnServerAgent/readiness.sh`

## Validation

Run the narrowest relevant check after edits, then broaden when touching shared behavior:

- `find . -name '*.json' -not -path './.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null`
- `bash -n liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `bash -n liveKitServerAgent/scripts/hooks/preinstall.sh`
- `ploinky start AchillesIDE/webmeetAgent`
- `ploinky status`
