# webmeetInfra/turnServerAgent Agent Guide

## Scope

Single Ploinky agent that runs Coturn as the dedicated WebMeet TURN/STUN
relay, using the shared-secret REST/ephemeral auth mechanism
(`use-auth-secret` / `static-auth-secret`). This agent owns TURN only; LiveKit
Server, Egress, and Redis live in the sibling `../liveKitServerAgent`.

## Mandatory Reading Order

1. Read the nearest parent `AGENTS.md` for workspace-wide rules.
2. Read `../docs/index.html` for the local documentation entry point.
3. Read `../docs/specs/matrix.md` and the relevant local DS files before changing behavior.
4. Read `../docs/specs/DS003-ploinky-runtime-invariants.md` before touching auth, routing, guest access, MCP, HTTP services, files, logs, or runtime configuration.
5. Read `../docs/specs/DS004-turn-server-agent.md` for this agent's contract: auth model, peer ACL/quota model, and fail-closed production rules.
6. Read `../docs/specs/DS002-livekit-server-agent.md` for the sibling agent's contract (LiveKit now consumes `WEBMEET_TURN_AUTH_SECRET`/`WEBMEET_TURN_HOST` to advertise `rtc.turn_servers`, but no longer runs Coturn itself).
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

The manifest sets `start: "sh /code/scripts/start-turn-server-agent.sh"` and
declares `health.readiness.script: "readiness.sh"` (a bare filename at this
directory's root — Ploinky's readiness-script validator rejects any `/` in
the name). The long-running supervisor must be a start-only service: using
the `agent` key would make Ploinky expect an MCP handshake and bypass the
script probe. There is no `readiness.protocol` and no published health port;
`readiness.sh` runs inside the running container.

`readiness.sh` cannot assume tools beyond what the pinned
`coturn/coturn:4.14.0-r0-debian` image actually ships. POSIX shell, `awk`,
`openssl`, `timeout`, and `turnutils_stunclient` were verified against the
exact digest. Their absence is a hard image-contract failure. Listener checks
use `/proc/net/{tcp,udp}` directly, and a no-secret STUN Binding request proves
the UDP listener answers. Do not pass TURN credentials to process arguments:
nested ploinky-box containers can share an enclosing `/proc` view. Relay-only
browser E2E is the end-to-end proof for REST authentication and the peer ACL;
there is no fallback probe path.

`preinstall.sh` runs on the host and uses `openssl` to validate production TLS
material. It rejects symlinked TLS path components before reading or changing
permissions, requires a public multi-label production hostname, and enforces
the same bounded quota/rate/lifetime values as the container start script. It
does not inspect or invoke a container engine.

The supervisor must not try to launch sibling Ploinky agents, for the same
reason as `liveKitServerAgent`: Ploinky resolves manifest `enable` edges
before this agent's container exists, so an in-container process has no view
of the host's runtime state.

## Secret-bearing runtime config

`WEBMEET_TURN_AUTH_SECRET` is `runtime: false`: Ploinky resolves it for the
host hook but omits it and its provenance marker from OCI environment metadata.
Preinstall atomically writes the fixed `.ploinky/data/webmeetSecrets/turn/auth-secret`
leaf behind a mode-`0700` host parent. The mounted directory/file are
`0755`/`0444` and read-only in the container so the pinned image's
`nobody:nogroup` UID can read them without a writable or env-based secret
channel. The startup script revalidates the file and creates `turnserver.conf`
itself in a private in-container directory with mode `0600`. Production TLS is
also mounted read-only. The shared secret has no `explicitOverride` and both
boundaries accept only the exact Ploinky-generated hexadecimal encoding.

## Key Paths

- `manifest.json`
- `scripts/start-turn-server-agent.sh`
- `scripts/hooks/preinstall.sh`
- `readiness.sh`
- `../docs/specs/DS004-turn-server-agent.md`
- `../docs/specs/DS003-ploinky-runtime-invariants.md`
- `../liveKitServerAgent/` — sibling agent that consumes `WEBMEET_TURN_AUTH_SECRET`/`WEBMEET_TURN_HOST` to advertise `rtc.turn_servers` to LiveKit clients

## Validation

Run the narrowest relevant check after edits, then broaden when touching shared behavior:

- `bash -n scripts/start-turn-server-agent.sh`
- `bash -n scripts/hooks/preinstall.sh`
- `bash -n readiness.sh`
- `find .. -name '*.json' -not -path '*/.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null`
- `ploinky start AchillesIDE/webmeetAgent`
- `ploinky status`
