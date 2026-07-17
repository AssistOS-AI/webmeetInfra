# webmeetInfra/liveKitServerAgent Agent Guide

## Scope

Single Ploinky agent that supervises Redis, LiveKit Server, LiveKit Egress, and
private health inside a pinned image. It contains no local relay, public TLS
proxy, certificate process, tunnel connector, or publication planner.

## Mandatory Reading Order

1. Read the nearest parent `AGENTS.md` for workspace-wide rules.
2. Read `../docs/index.html` for the local documentation entry point.
3. Read `../docs/specs/matrix.md` and the relevant local DS files before changing behavior.
4. Read `../docs/specs/DS003-ploinky-runtime-invariants.md` before touching auth, routing, guest access, MCP, HTTP services, files, logs, or runtime configuration.
5. Read `../docs/specs/DS002-livekit-server-agent.md` for the agent contract and the responsibilities of each supervised service.
6. Read `../docs/specs/DS001-coding-style.md` for coding style, module structure, and test-organization rules.

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

The manifest sets `agent: "sh /code/scripts/start-livekit-server-agent.sh"` and
uses managed TCP readiness. The summary probe passes only after Redis, LiveKit
Server, LiveKit Egress, Egress semantic health, and expected socket ownership
are ready. Detailed health is served only on the unmounted Unix socket
`/run/ploinky/livekit-supervisor.sock`.

The preinstall hook consumes the immutable topology generation and generates
LiveKit with loopback HTTP/Twirp on `7880`, a literal configured public IPv4,
`use_external_ip: false`, one UDP mux on `7882`, and TCP media disabled. Public
signaling and private Twirp use their declared Router services. External TURN
credentials are brokered to authorized consumers; no long-term relay secret
enters this agent.

The supervisor must not try to launch sibling Ploinky agents: Ploinky resolves
manifest `enable` edges before this agent's container exists, and an in-process
`ploinky` call from inside the container has no view of the host's runtime
state. Every required service must therefore be installed in the image and
supervised by the script directly.

Generated config under `.data/liveKitServerAgent/generated/` is rebuilt every
preinstall and must not contain secrets that leak outside the workspace.
Durable state lives under `.ploinky/data/webmeet/` (Redis data and recordings).

## Key Paths

- `manifest.json`
- `scripts/start-livekit-server-agent.sh`
- `scripts/hooks/preinstall.sh`
- `scripts/health/livekit-server-agent-health.sh`
- `scripts/health/supervisor-health.mjs`
- `../docs/specs/DS002-livekit-server-agent.md`
- `../docs/specs/DS003-ploinky-runtime-invariants.md`

## Validation

Run the narrowest relevant check after edits, then broaden when touching shared behavior:

- `sh -n scripts/start-livekit-server-agent.sh`
- `sh -n scripts/hooks/preinstall.sh`
- `sh -n scripts/health/livekit-server-agent-health.sh`
- `node --check scripts/health/supervisor-health.mjs`
- `find .. -name '*.json' -not -path '*/.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null`
- `ploinky start AchillesIDE/webmeetAgent`
- `ploinky status`
