# webmeetInfra/liveKitServerAgent Agent Guide

## Scope

Single Ploinky agent that supervises the LiveKit media runtime (Redis,
LiveKit Server, LiveKit Egress) inside one container. TURN/STUN relay lives
in the sibling `../turnServerAgent`; this agent only configures
`rtc.turn_servers` so LiveKit Server can mint expiring credentials and
advertise that relay to browser TURN clients. Signaling TLS termination lives
in `basic/web-publishing`, not here.

## Mandatory Reading Order

1. Read the nearest parent `AGENTS.md` for workspace-wide rules.
2. Read `../docs/index.html` for the local documentation entry point.
3. Read `../docs/specs/matrix.md` and the relevant local DS files before changing behavior.
4. Read `../docs/specs/DS003-ploinky-runtime-invariants.md` before touching auth, routing, guest access, MCP, HTTP services, files, logs, or runtime configuration.
5. Read `../docs/specs/DS002-livekit-server-agent.md` for this agent's contract and the responsibilities of each supervised service.
6. Read `../docs/specs/DS004-turn-server-agent.md` for the sibling TURN agent's contract (shared secret, peer ACL, production TLS).
7. Read `../docs/specs/DS001-coding-style.md` for coding style, module structure, and test-organization rules.

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

The manifest sets `start: "sh /code/scripts/start-livekit-server-agent.sh"`
and `health.readiness.script: "readiness.sh"` (a bare filename at this
directory's root — Ploinky's readiness-script validator rejects any `/` in
the name). The long-running supervisor must be a start-only service: using
the `agent` key would make Ploinky expect an MCP handshake and bypass the
script probe. There is no `readiness.protocol` and no published health port
anymore. `readiness.sh` runs inside the container and uses the pinned image's
required `nc` binary to check Redis, LiveKit Server, and Egress on fixed
internal ports. Missing `nc` is a hard image-contract failure; there are no
alternate probe paths or environment-controlled port overrides.

The supervisor must not try to launch sibling Ploinky agents: Ploinky resolves
manifest `enable` edges before this agent's container exists, and an in-process
`ploinky` call from inside the container has no view of the host's runtime
state. Every required service must therefore be installed in the image and
supervised by the script directly.

Generated config under `.data/liveKitServerAgent/generated/` is rebuilt every
preinstall through confined, non-symlinked directories and atomic leaf
replacement; it must not contain secrets that leak outside the workspace.
Durable state lives under `.ploinky/data/webmeet/` (Redis dump, recordings).
There is no longer a `.ploinky/data/webmeetTls/...` volume for this agent —
that was Nginx/Certbot state, both removed.

`WEBMEET_TURN_AUTH_SECRET` is declared identically here and in
`../turnServerAgent/manifest.json` (`sharedGeneratedSecret: true`,
`runtime: false`, without `explicitOverride`) so Ploinky's workspace-scoped generated-secret
mechanism resolves both agents to the exact same secret and ignores operator
replacement values. `WEBMEET_TURN_HOST` is ordinary non-secret topology input
with profile defaults locally and an explicit production value. The hook validates the exact generated encoding before
`preinstall.sh` inlines it into the generated `livekit.yaml`'s
`rtc.turn_servers[].secret`, the same way the LiveKit API secret is already
inlined into the same file — never a `secret_file`, never the command line,
never logged. All three credentials are host-hook-only and absent from OCI
`Config.Env`; the container's re-exec scrub remains defense in depth before
starting the supervisor, Redis, LiveKit, or Egress processes.
This is process-environment minimization, not isolation from another enabled
uid-0 agent: such an agent can still traverse LiveKit's process root and read
the root-owned private config. That broader nested-runtime boundary is
documented in DS003 and must not be patched with agent-specific fallbacks.

`WEBMEET_LIVEKIT_LOG_LEVEL` defaults to `warn`. LiveKit 1.11's `info` RTC
session event includes publisher SDP, including ICE credentials, fingerprints,
and candidate addresses; `info` and `debug` are explicit sensitive-diagnostic
opt-ins and the preinstall hook warns when selected.

## Key Paths

- `manifest.json`
- `../../container-image-builds/images/livekit-server-agent/Dockerfile` — centralized image definition for this build context
- `scripts/start-livekit-server-agent.sh`
- `scripts/hooks/preinstall.sh`
- `readiness.sh`
- `../docs/specs/DS002-livekit-server-agent.md`
- `../docs/specs/DS004-turn-server-agent.md`
- `../docs/specs/DS003-ploinky-runtime-invariants.md`
- `../turnServerAgent/` — sibling agent that now owns the TURN relay

## Validation

Run the narrowest relevant check after edits, then broaden when touching shared behavior:

- `bash -n scripts/start-livekit-server-agent.sh`
- `bash -n scripts/hooks/preinstall.sh`
- `bash -n readiness.sh`
- `find .. -name '*.json' -not -path '*/.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null`
- `ploinky start AchillesIDE/webmeetAgent`
- `ploinky status`
