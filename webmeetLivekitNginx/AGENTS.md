# webmeetInfra/webmeetLivekitNginx Agent Guide

## Scope

TLS terminator and reverse proxy in front of the LiveKit signaling endpoint. Replaces the previous host-system Nginx for `livekit-skills.axiologic.dev`.

## Mandatory Reading Order

1. Read the nearest parent `AGENTS.md` for workspace-wide rules.
2. Read `../docs/index.html` for the local documentation entry point.
3. Read `../docs/specs/matrix.md` and the relevant local DS files before changing behavior.
4. Read `../docs/specs/DS007-ploinky-runtime-invariants.md` before touching auth, routing, guest access, MCP, HTTP services, files, logs, or runtime configuration.
5. Read `../docs/specs/DS008-livekit-nginx-agent.md` for the TLS-terminator contract and shared-volume layout.
6. Read `../docs/specs/DS009-livekit-certbot-agent.md` for how cert renewal is delivered into the shared `/etc/letsencrypt` volume.

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

Runs `nginx:${WEBMEET_NGINX_VERSION}` with `network.mode: "host"`. The preinstall hook generates `nginx.conf` and a small `start.sh` that watches the cert file and reloads nginx on rotation.

## Key Paths

- `manifest.json`
- `scripts/hooks/preinstall.sh`
- `../docs/specs/DS008-livekit-nginx-agent.md`
- `../docs/specs/DS007-ploinky-runtime-invariants.md`

## Validation

Run the narrowest relevant check after edits, then broaden when touching shared behavior:

- `ploinky status`
- `curl -fsSI -o /dev/null https://${WEBMEET_TLS_HOSTNAME}/` from the deployment host
