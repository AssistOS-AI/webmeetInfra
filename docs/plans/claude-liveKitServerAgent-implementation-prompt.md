# Claude Implementation Prompt

You are working in `/Users/danielsava/work/file-parser`.

Goal: implement the plan in
`/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra/docs/plans/liveKitServerAgent-consolidation-plan.md`.

## Required Reading

Read these first:

- `/Users/danielsava/work/file-parser/CLAUDE.md`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/CLAUDE.md`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra/CLAUDE.md`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra/docs/specs/matrix.md`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra/docs/specs/DS007-ploinky-runtime-invariants.md`
- The full consolidation plan named above

Do not edit `.ploinky/repos` shadow checkouts.
Do not add AI/coding-agent attribution anywhere.
Do not print or copy DockerHub tokens, local auth passwords, JWTs, or generated
secrets.

## Implementation Scope

Implement a single Ploinky infra agent named `liveKitServerAgent` under:

`/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra/liveKitServerAgent`

This agent replaces the split WebMeet infra agents:

- `stack`
- `webmeetRedis`
- `webmeetCoturn`
- `webmeetLivekitServer`
- `webmeetLivekitEgress`
- `webmeetLivekitNginx`
- `webmeetLivekitCertbot`

The manifest `agent` command must call a shell script from the repo, for
example:

```json
"agent": "sh /code/scripts/start-livekit-server-agent.sh"
```

The shell script runs inside the `liveKitServerAgent` container. It must
supervise the required runtime services. Do not make the script launch sibling
Ploinky agents or child Docker/Podman containers.

## Files To Add

Add:

- `liveKitServerAgent/manifest.json`
- `liveKitServerAgent/Dockerfile`
- `liveKitServerAgent/README.md`
- `liveKitServerAgent/CLAUDE.md`
- `liveKitServerAgent/AGENTS.md`
- `liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `liveKitServerAgent/scripts/hooks/preinstall.sh`
- `liveKitServerAgent/scripts/health/livekit-server-agent-health.sh`
- `.github/workflows/publish-livekit-server-agent.yml`

Update:

- `README.md`
- `CLAUDE.md`
- `AGENTS.md`
- `docs/index.html`
- `docs/specs/matrix.md`
- all affected local DS specs
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetAgent/manifest.json`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetLivekitAiAgent/manifest.json`

Keep `AGENTS.md` and `CLAUDE.md` aligned when either is touched.

## Docker Image

Use this image unless there is a strong reason to rename it consistently
everywhere:

```text
assistos/livekit-server-agent:webmeet-infra
```

Create `liveKitServerAgent/Dockerfile`.

Recommended Dockerfile strategy:

- Use `livekit/egress` as final base if practical.
- Copy `/livekit-server` from `livekit/livekit-server`.
- Install Redis, Coturn, Nginx, Certbot, curl, CA certificates, and `tini`.
- Validate at build time that `egress`, `livekit-server`, `redis-server`,
  `turnserver`, `nginx`, and `certbot` are available.
- If the Egress base image cannot support the required package install or
  architectures, document the decision and choose a working final base.

## GitHub Workflow

Create:

`/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra/.github/workflows/publish-livekit-server-agent.yml`

Mirror the existing bwrap-runner workflow at:

`/Users/danielsava/work/file-parser/basic/.github/workflows/publish-bwrap-runner.yml`

Required workflow properties:

- Manual `workflow_dispatch` only.
- Docker Hub namespace/user: `assistos`.
- Docker Hub token source: `${{ secrets.DOCKERHUB_TOKEN }}`.
- Do not read `~/DOCKERHUB_TOKEN` in GitHub Actions.
- Use Docker Buildx and metadata actions.
- Publish raw tag `webmeet-infra` and sha-prefixed tag
  `webmeet-infra-<sha>`.
- Start with `linux/amd64,linux/arm64`; if upstream Egress does not support
  `arm64`, reduce platforms and document why.
- Use `provenance: false`.

Do not dispatch the workflow unless explicitly asked.

## Manifest Requirements

The new manifest must:

- Use the published image reference, with an env-configurable tag if helpful.
- Set `agent` to the startup shell script.
- Set `readiness.protocol` to `tcp`.
- Put the health port first in profile `ports`, for example
  `127.0.0.1:17000:17000`.
- Mount generated config from `.ploinky/agents/liveKitServerAgent`.
- Mount durable state from `.ploinky/data/webmeet` and
  `.ploinky/data/webmeetTls`.
- Preserve current derived secret labels for LiveKit and TURN so existing
  consumers keep compatible credentials.
- Provide compatibility network aliases:
  `liveKitServerAgent`, `webmeetLivekitServer`, `webmeetLivekitEgress`,
  `webmeetRedis`, and `webmeetCoturn`.

Default/dev should use the bridge `webmeet` network with localhost-bound
published ports.

Prod should prefer host networking to preserve LiveKit WebRTC and Nginx
behavior, with Redis, LiveKit, and Egress using localhost internally.

Verify whether Egress needs privileged container mode. The old
`capabilities: ["SYS_ADMIN"]` field may not be enforced by Ploinky. If
privilege is needed, use documented `containerSecurity.privileged` or add
proper Ploinky support with tests and specs.

## Startup And Preinstall

`scripts/hooks/preinstall.sh` runs on the host. It should generate:

- `livekit.yaml`
- `egress.yaml`
- Nginx config
- Certbot helper scripts
- any small supervisor config files

Only write generated inputs under `.ploinky/agents/liveKitServerAgent` and
durable service state under `.ploinky/data/...`.

`scripts/start-livekit-server-agent.sh` runs inside the container. It should:

- Start Redis.
- Wait for Redis.
- Start Coturn.
- Start LiveKit Server.
- Wait for LiveKit.
- Start LiveKit Egress.
- Start Certbot/Nginx only for prod when enabled.
- Start a small health endpoint only after required services are ready.
- Trap termination signals.
- Stop children cleanly.
- Exit nonzero when a required service exits unexpectedly.
- Avoid logging secrets or full generated config contents.

## Consumer Migration

Update:

- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetAgent/manifest.json`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetLivekitAiAgent/manifest.json`

Replace `webmeetInfra/stack` with `webmeetInfra/liveKitServerAgent`.

Keep existing service URLs working through aliases when possible. If prod needs
`host.containers.internal`, update profile env and docs explicitly.

## Docs And Specs

Update local docs and specs in the same change. Specs are source of truth.

At minimum:

- Explain that `liveKitServerAgent` is the single WebMeet infra Ploinky agent.
- Explain that Redis, Coturn, LiveKit Server, Egress, Nginx, and Certbot are
  internal supervised services now.
- Mark old split agents as retired or compatibility-only.
- Explain why the manifest `agent` script does not launch sibling Ploinky
  agents.
- Document the Docker Hub image and manual publish workflow.
- Document the GitHub secret name `DOCKERHUB_TOKEN`, not the token value.

## Validation

Run the narrowest checks first:

```sh
cd /Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra
find . -name '*.json' -not -path './.git/*' -print0 | xargs -0 -n1 python3 -m json.tool >/dev/null
bash -n liveKitServerAgent/scripts/start-livekit-server-agent.sh
bash -n liveKitServerAgent/scripts/hooks/preinstall.sh
git diff --check
```

Build the image locally:

```sh
cd /Users/danielsava/work/file-parser/AssistOSExplorer/webmeetInfra
docker build -t assistos/livekit-server-agent:webmeet-infra liveKitServerAgent
```

Use Podman if this machine is configured for Podman instead of Docker.

Then start through Ploinky:

```sh
cd /Users/danielsava/work/file-parser
ploinky start AchillesIDE/webmeetAgent
ploinky status
```

Smoke the health endpoint, LiveKit signaling, Redis, Coturn, Egress, and
WebMeet room creation. Run prod/TLS checks separately if prod behavior changed.

Do not deploy to `skills.axiologic.dev` or dispatch the Docker Hub publishing
workflow unless explicitly asked.

## Final Report

Report:

- Files changed.
- Image name and tag.
- Workflow path.
- Validation commands run and results.
- Any unresolved risks, especially Egress privileges or multi-arch limits.
