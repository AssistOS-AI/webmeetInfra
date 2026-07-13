---
id: DS003
title: Ploinky Runtime Invariants
status: implemented
owner: webmeet-infra-team
summary: Captures the Ploinky routing, authentication, guest, secure-wire, sandbox, and documentation invariants that must remain in local context when changing this agent.
---

# DS003 - Ploinky Runtime Invariants

## Introduction

This specification makes the Ploinky runtime and security invariants local to `webmeetInfra`. Future work from inside this agent directory must not rely on external memory of Ploinky core behavior; the local specs must carry the same high-level constraints that Ploinky defines in its routing and security model.

The authoritative upstream contracts are Ploinky `docs/specs/DS005-routing-and-web-surfaces.md` and `docs/specs/DS011-security-model.md`. This file restates only the invariants that affect this agent's implementation and documentation.

## Core Content

`webmeetInfra` must treat the Ploinky router as the browser and MCP trust broker. Browser surfaces, first-party MCP calls, delegated MCP calls, uploads, blobs, and manifest-declared HTTP services are expected to enter through the router so route authentication, session handling, invocation minting, and audit behavior can apply. Direct agent ports are implementation details even when they are bound to localhost.

Executable MCP operations must be authorized by router-minted request JWTs. The launcher/router may derive per-agent request secrets from `PLOINKY_MASTER_KEY`, but the agent runtime receives only its own `PLOINKY_AGENT_ID`, `PLOINKY_AGENT_SECRET`, and compatibility `PLOINKY_AGENT_PRINCIPAL`. Agents must never receive, derive, or require `PLOINKY_MASTER_KEY` or the retired `PLOINKY_DERIVED_MASTER_KEY`. Code must not invent alternate bearer-token, client-secret, or caller-header authorization paths around the router's secure-wire model.

Ploinky-owned generated secrets are resolved by the launcher before agent code runs. Agent-owned generated secrets use `generatedSecret: true` for manifest env entries or `{{generatedSecret:NAME}}` for runtime-resource templates; both are scoped to the current agent identity and ignore operator-supplied values. Shared generated credentials that must be identical across agents use `sharedGeneratedSecret: true` and derive from the source env name. Agents consume only the resolved values and never receive the master derivation key. Agents must not invent random persistent agent secrets or require manual configuration for workspace-owned LiveKit, TURN, OnlyOffice, DPU, recording, webhook, or data-encryption secrets. External third-party credentials remain explicitly configured.

The compact `x-ploinky-auth-info` header is not a secure grant by itself. Any HTTP service that receives that header must trust it only when it arrived through a declared Ploinky HTTP service route and, for guest services, only after validating the router-issued invocation token and the expected guest role or scope. Caller-supplied copies of identity headers must be rejected as authoritative input.

Guest access must remain scoped to the route shape declared by the owning manifest. Manifest-level `guest: true` exposes the agent as a normal guest agent and should still enforce limitations from `usr.roles`. A `routerAccess.httpRoutes` entry with `access: "guest"` exposes only the declared agent-owned HTTP path and mints or reuses a route-scoped guest session according to Ploinky's current guest policy. An `httpServices` entry with `access: "guest"` exposes only the declared HTTP prefix and mints or reuses a service-scoped guest session. Product-specific public paths must be declared in the agent manifest rather than hard-coded in Ploinky core.

Agent code must enforce its own domain authorization. Ploinky route authentication identifies the caller and signs the invocation, but it does not grant every domain operation. Sensitive actions must check the verified user, roles, scopes, target resource, workspace path, and agent-local policy before reading or mutating state.

Runtime isolation is defense in depth, not a hostile multi-tenant guarantee. Containers, bubblewrap, and Seatbelt reduce host exposure, but enabled agent code remains trusted operator-controlled code inside one workspace. Manifest volumes, runtime resources, lifecycle hooks, and network access are intentional grants and must be reviewed as part of the agent contract.

In a nested ploinky-box, sibling containers can share an enclosing `/proc` view. Credentials needed only by host config-generation hooks must therefore declare `runtime: false`: Ploinky resolves them for the trusted host hook, but excludes them and their provenance markers from OCI `Config.Env` and sandbox process environments. The host hook still sees the value during its bounded execution; credentials must never be placed in command-line arguments or ordinary runtime env.

This minimization is not hostile multi-tenant isolation. A compromised enabled agent running as uid 0 can traverse a root-owned LiveKit process root and read its owner-only generated config, including credentials LiveKit must retain to mint participant and TURN credentials. Preventing that lateral access requires per-agent PID/user-namespace isolation or a non-root LiveKit/config ownership design at the generic runtime/image boundary; agent-specific discovery or fallback logic is forbidden. Enabled uid-0 agent code remains inside the trusted operator-controlled workspace boundary.

File and static-content handling must stay workspace-confined. Paths must be resolved relative to the workspace root, agent root, configured data directory, or explicit runtime volume. Security-sensitive lifecycle hooks must reject symlinked directory components and either reject or atomically replace pre-existing secret-bearing leaf symlinks before writing or changing permissions. Code must not assume host-specific absolute paths, follow symlink escapes, or place secrets in static roots, plugin assets, HTML documentation, logs, transcripts, screenshots, or test fixtures.

Logs and user-facing errors must not expose secrets, cookies, bearer tokens, invocation JWTs, API keys, raw prompts, hidden policy text, or internal payloads. Detailed diagnostics belong behind explicit debug modes and must still redact sensitive values before persistence.

LiveKit 1.11 cannot redact SDP from its `info` RTC-session event, so WebMeet infrastructure defaults it to `warn`. Selecting `info` or `debug` is an explicit sensitive-diagnostic operation; those logs must not be retained or shared as ordinary operational artifacts.

Agent-local contract:

- Manifests: `webmeetInfra/liveKitServerAgent/manifest.json` and `webmeetInfra/turnServerAgent/manifest.json`.
- Role: `liveKitServerAgent` supervises the LiveKit media runtime (Redis, LiveKit Server, LiveKit Egress); `turnServerAgent` runs Coturn as a dedicated TURN/STUN relay. Neither runs Nginx/Certbot; the signaling edge lives in `basic/web-publishing`.
- Authentication: Both agents run as dependencies of `webmeetAgent` / `webmeetLivekitAiAgent` and must not expose application guest or admin policy themselves. `WEBMEET_TURN_AUTH_SECRET` is declared identically (`sharedGeneratedSecret: true`, `runtime: false`, without `explicitOverride`) in both manifests so Ploinky's workspace-scoped generated-secret mechanism resolves both to one value, ignores operator-supplied replacements, and withholds it from runtime environment metadata.
- HTTP service surface: No infrastructure manifest declares public HTTP services; application-facing guest routes belong to `webmeetAgent`.
- Persistent state: Generated LiveKit/Egress/Redis config is controlled by `liveKitServerAgent` under `.data/liveKitServerAgent/generated/...`. `turnServerAgent` generates its secret-bearing Coturn config only in a private in-container runtime directory. Its host preinstall hook atomically writes the `runtime: false` shared secret beneath the owner-confined `.ploinky/data/webmeetSecrets/turn/` parent and mounts that leaf directory read-only for the fixed non-root Coturn UID. Relative manifest volume paths must be workspace-confined; explicit absolute host paths are permitted only as deliberate manifest grants. Durable recording data belongs under `.ploinky/data/webmeet/recordings`, durable Redis state under `.ploinky/data/webmeet/redis`, and production TURN TLS material under `.ploinky/data/webmeetTls/turn/`.
- Documentation: `docs/index.html`
- Validation: `ploinky start AchillesIDE/webmeetAgent` plus `ploinky status` confirm both agents report ready.
- Supervisor scope: `liveKitServerAgent/scripts/start-livekit-server-agent.sh` and `turnServerAgent/scripts/start-turn-server-agent.sh` may each only manage processes installed inside their own image. Neither may invoke `ploinky` or otherwise try to start sibling agents, because Ploinky resolves `enable` edges before the container is created.
- Runtime secret minimization: LiveKit's TURN and API credentials and Coturn's shared secret are host-hook-only env entries. They are absent from OCI `Config.Env`, later container exec environments, bwrap/Seatbelt process env, and process arguments. The bounded host hooks still receive the generated values to materialize confined config or the read-only TURN startup file.

## Decisions & Questions

### Question #1: Why duplicate Ploinky invariants inside every agent spec set?

Response:
Coding work often starts from an individual agent directory, where only local guidance may be read before changes are made. Keeping these Ploinky invariants in the local specification set prevents agents from accidentally treating router auth, guest mode, direct ports, or invocation headers as agent-specific implementation details that can be bypassed.

### Question #2: Why is route authentication not enough for domain authorization?

Response:
Ploinky establishes who the caller is and signs the invocation path, but domain ownership remains inside the agent. The agent knows which files, records, rooms, leads, secrets, repositories, media objects, or infrastructure controls are safe for that caller. Each agent must therefore enforce its own resource policy after reading verified auth context.

### Question #3: Why must generated secrets be launcher-resolved instead of derived inside an agent?

Response:
Keeping `PLOINKY_MASTER_KEY` and the retired derived-master surface out of containers prevents one enabled agent from becoming a derivation oracle for another agent's credentials. Ploinky resolves each generated or shared-generated manifest entry before startup, and the infrastructure process receives only the specific LiveKit or TURN value it declared.

### Question #4: Why do the hooks still validate launcher-generated secret encoding?

Response:
Manifest resolution is the primary ownership boundary, but each hook and
container start script is also executable directly during tests or operator
diagnostics. Requiring the expected 64-character lowercase hexadecimal
encoding prevents newline or directive injection even when a caller bypasses
normal manifest resolution, without adding an alternate credential source or
agent-specific Ploinky coupling.

## Conclusion

`webmeetInfra` remains compatible with Ploinky only while it preserves router-mediated entry, secure-wire invocation, scoped guest behavior, explicit manifest-declared HTTP services, workspace-confined storage, redacted logging, and local domain authorization. Any source change that affects these contracts must update this specification, the local docs, and the local guide files in the same change set.
