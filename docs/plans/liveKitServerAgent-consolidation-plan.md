# liveKitServerAgent Consolidation Plan

## Goal

Consolidate the current WebMeet infrastructure Ploinky agents into one
Ploinky agent named `liveKitServerAgent`. The single agent should start the
runtime services from an `agent` shell command in its manifest, while the
service binaries come from a purpose-built Docker image published to Docker
Hub.

The consolidated agent replaces these current Ploinky agents:

- `stack`
- `webmeetRedis`
- `webmeetCoturn`
- `webmeetLivekitServer`
- `webmeetLivekitEgress`
- `webmeetLivekitNginx`
- `webmeetLivekitCertbot`

## Important Runtime Constraint

Ploinky resolves manifest `enable` dependencies before startup. A manifest
`agent` command runs inside that agent's container, after Ploinky has already
created the container. Therefore `liveKitServerAgent` should not try to launch
other Ploinky agents from inside its shell script.

Use the shell script as an in-container supervisor for Redis, Coturn, LiveKit
Server, LiveKit Egress, Nginx, Certbot, and a small health endpoint.

Host-side preparation, such as generating `livekit.yaml`, `egress.yaml`, Nginx
config, and Certbot scripts, should remain in a `preinstall` lifecycle hook.
Lifecycle hooks are trusted host/runtime code; generated files and durable data
must stay under `.ploinky/`.

## Prior Docker Hub Publishing Convention

The previous bwrap-runner image workflow lives at:

`/Users/danielsava/work/file-parser/basic/.github/workflows/publish-bwrap-runner.yml`

Observed convention:

- Docker Hub namespace: `assistos`
- Workflow trigger: `workflow_dispatch` only
- Docker Hub username in workflow: `assistos`
- Docker Hub password source: repository secret `DOCKERHUB_TOKEN`
- Build actions:
  - `docker/setup-qemu-action@v3`
  - `docker/setup-buildx-action@v3`
  - `docker/login-action@v3`
  - `docker/metadata-action@v5`
  - `docker/build-push-action@v6`
- Tags:
  - raw stable tag
  - sha tag with stable tag prefix
- Previous workflow pushed `linux/amd64,linux/arm64`
- `provenance: false`

Previous Codex session search found the old manual push instruction used
`~/DOCKERHUB_TOKEN` to push to `https://hub.docker.com/repositories/assistos`.
Do not copy local token values into docs, workflows, prompts, or logs. The
repository workflow must use only `${{ secrets.DOCKERHUB_TOKEN }}`.

## Image Naming

Use this Docker Hub image for the consolidated runtime:

```text
assistos/livekit-server-agent:webmeet-infra
```

The workflow should also publish a sha-qualified tag:

```text
assistos/livekit-server-agent:webmeet-infra-<sha>
```

If the team prefers a more explicit repository name, use
`assistos/webmeet-livekit-server-agent` consistently in the manifest, workflow,
docs, and tests. Do not mix image names.

## Target Files

Create these files:

- `liveKitServerAgent/manifest.json`
- `liveKitServerAgent/Dockerfile`
- `liveKitServerAgent/README.md`
- `liveKitServerAgent/CLAUDE.md`
- `liveKitServerAgent/AGENTS.md`
- `liveKitServerAgent/scripts/start-livekit-server-agent.sh`
- `liveKitServerAgent/scripts/hooks/preinstall.sh`
- `liveKitServerAgent/scripts/health/livekit-server-agent-health.sh`
- `.github/workflows/publish-livekit-server-agent.yml`

Update these existing files:

- `README.md`
- `CLAUDE.md`
- `AGENTS.md`
- `docs/index.html`
- `docs/specs/matrix.md`
- `docs/specs/DS000-vision.md`
- `docs/specs/DS002-stack-agent.md`
- `docs/specs/DS003-livekit-server-agent.md`
- `docs/specs/DS004-livekit-egress-agent.md`
- `docs/specs/DS005-coturn-agent.md`
- `docs/specs/DS006-redis-agent.md`
- `docs/specs/DS007-ploinky-runtime-invariants.md`
- `docs/specs/DS008-livekit-nginx-agent.md`
- `docs/specs/DS009-livekit-certbot-agent.md`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetAgent/manifest.json`
- `/Users/danielsava/work/file-parser/AssistOSExplorer/webmeetLivekitAiAgent/manifest.json`

## Dockerfile Plan

Create `liveKitServerAgent/Dockerfile`.

Recommended approach:

1. Use `livekit/egress` as the final base image if practical, because Egress
   has the largest dependency surface.
2. Copy the `/livekit-server` binary from `livekit/livekit-server`.
3. Install Redis, Coturn, Nginx, Certbot, shell utilities, CA certificates,
   curl, and a minimal init such as `tini` into the final image.
4. Validate at build time that `egress`, `livekit-server`, `redis-server`,
   `turnserver`, `nginx`, and `certbot` exist.
5. Keep canonical startup logic in repository scripts under
   `liveKitServerAgent/scripts/`. The image may copy them for image-level smoke
   checks, but the Ploinky manifest should invoke the script from `/code`.

Dockerfile shape:

```Dockerfile
ARG LIVEKIT_SERVER_IMAGE=livekit/livekit-server:v1.9.1
ARG LIVEKIT_EGRESS_IMAGE=livekit/egress:latest

FROM ${LIVEKIT_SERVER_IMAGE} AS livekit-server

FROM ${LIVEKIT_EGRESS_IMAGE} AS runtime
USER root

RUN set -eu; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl tini redis-server coturn nginx certbot; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache ca-certificates curl tini redis coturn nginx certbot; \
    else \
      echo "Unsupported base image package manager" >&2; \
      exit 1; \
    fi

COPY --from=livekit-server /livekit-server /usr/local/bin/livekit-server

RUN set -eu; \
    command -v egress; \
    command -v livekit-server; \
    command -v redis-server; \
    command -v turnserver; \
    command -v nginx; \
    command -v certbot

WORKDIR /code
ENTRYPOINT ["tini", "--"]
CMD ["sh", "/code/scripts/start-livekit-server-agent.sh"]
```

Implementation must adjust the package names if the chosen `livekit/egress`
base is not Debian/Ubuntu or Alpine. If `livekit/egress` cannot be used as the
final base, choose a Debian or Ubuntu final base and copy or install the Egress
runtime in a documented, tested way.

## GitHub Actions Workflow Plan

Create `.github/workflows/publish-livekit-server-agent.yml` in the
`webmeetInfra` repository.

Mirror the bwrap-runner publishing pattern:

```yaml
name: Publish liveKitServerAgent image

on:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: publish-livekit-server-agent-image
  cancel-in-progress: false

env:
  IMAGE_NAME: assistos/livekit-server-agent
  IMAGE_TAG: webmeet-infra

jobs:
  publish:
    name: Build and push Docker Hub image
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: assistos
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=${{ env.IMAGE_TAG }}
            type=sha,prefix=${{ env.IMAGE_TAG }}-

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ./liveKitServerAgent
          file: ./liveKitServerAgent/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          provenance: false
```

If any upstream image does not publish `linux/arm64`, reduce `platforms` to the
supported platform set and document the reason in the DS spec and README.

## Manifest Plan

Create `liveKitServerAgent/manifest.json` as the only enabled infra agent.

Core manifest requirements:

- `container`: `docker.io/assistos/livekit-server-agent:webmeet-infra`
- `agent`: `sh /code/scripts/start-livekit-server-agent.sh`
- `readiness.protocol`: `tcp`
- Health port first in each profile's `ports`, for example
  `127.0.0.1:17000:17000`
- Volumes for generated config under `.ploinky/agents/liveKitServerAgent/...`
- Volumes for durable data under `.ploinky/data/webmeet/...`
- Volumes for TLS state under `.ploinky/data/webmeetTls/...`
- Preserve derived secret labels:
  - LiveKit shared API credentials use repo `webmeet`, agent
    `shared-livekit`
  - TURN shared secret uses repo `webmeet`, agent `shared-turn`
- Add compatibility network aliases:
  - `liveKitServerAgent`
  - `webmeetLivekitServer`
  - `webmeetLivekitEgress`
  - `webmeetRedis`
  - `webmeetCoturn`

Default/dev profile:

- Use bridge network `webmeet`
- Publish local development ports only on `127.0.0.1`
- Keep LiveKit, Redis, TURN, and health endpoints reachable for local smoke
  tests

Prod profile:

- Prefer host networking to preserve LiveKit WebRTC UDP and Nginx TLS behavior
- Use localhost inside the container for Redis, LiveKit, and Egress
- Keep public exposure deliberate: HTTP/HTTPS, LiveKit TCP, and configured UDP
  ranges only

Egress security:

- Verify whether `livekit/egress` actually needs elevated privileges in this
  deployment.
- The old `capabilities: ["SYS_ADMIN"]` field appears to be agent-local data,
  not a Ploinky-enforced runtime setting. If elevation is required, use the
  documented Ploinky `containerSecurity.privileged` setting or add explicit
  runtime support in Ploinky with tests and specs.

## Startup Script Plan

`scripts/start-livekit-server-agent.sh` should:

1. Use `set -eu`.
2. Create runtime directories.
3. Start Redis.
4. Wait for Redis TCP readiness.
5. Start Coturn.
6. Start LiveKit Server with generated `livekit.yaml`.
7. Wait for LiveKit TCP readiness.
8. Start LiveKit Egress with generated `egress.yaml`.
9. In prod, start or schedule Certbot maintenance according to env.
10. In prod, start Nginx after certificate/bootstrap rules are satisfied.
11. Start a small health listener on `17000` only after required services are
    ready.
12. Trap `TERM` and `INT`, stop children, and exit nonzero when a required
    child exits unexpectedly.

The script must not print secrets, derived keys, LiveKit API secrets, TURN
secrets, JWTs, or full generated config contents.

## Preinstall Plan

`scripts/hooks/preinstall.sh` should:

1. Generate `livekit.yaml`.
2. Generate `egress.yaml`.
3. Generate Nginx config and Certbot helper scripts for prod.
4. Write only under `.ploinky/agents/liveKitServerAgent` and
   `.ploinky/data/...`.
5. Preserve the current profile-specific defaults from the old manifests.
6. Refuse invalid prod combinations early with clear errors.
7. Never write plaintext secrets outside Ploinky-generated runtime files.

## Consumer Migration

Update:

- `AssistOSExplorer/webmeetAgent/manifest.json`
- `AssistOSExplorer/webmeetLivekitAiAgent/manifest.json`

Replace `webmeetInfra/stack` with `webmeetInfra/liveKitServerAgent`.

Keep existing URLs working through compatibility aliases when possible. If prod
must use `host.containers.internal`, update the profile-specific environment in
the consumers and document the difference.

## Stack Compatibility

Preferred migration:

1. First change `stack` into a compatibility shim that enables only
   `webmeetInfra/liveKitServerAgent`.
2. Update direct consumers to enable `webmeetInfra/liveKitServerAgent`.
3. Mark the old split-service agents as retired in docs.
4. Remove the old agents in a later cleanup after migration is verified.

If the requirement is interpreted strictly as "all other agents must disappear
now", remove or archive the old agent directories in the same change, but only
after updating docs and consumers.

## Documentation Plan

Update docs and specs in the same change as behavior changes.

Minimum documentation updates:

- `README.md`: new single-agent runtime and publishing workflow.
- `docs/index.html`: point readers at the consolidated agent.
- `docs/specs/matrix.md`: add/update the liveKitServerAgent row and mark old
  agents retired or compatibility-only.
- `DS002`: stack is compatibility-only or retired.
- `DS003`: liveKitServerAgent owns LiveKit Server plus consolidated supervisor.
- `DS004` to `DS009`: explain each service is now an internal supervised
  service of `liveKitServerAgent`.
- `DS007`: document the single-container runtime boundary, generated file
  locations, secrets handling, and why the agent script does not launch sibling
  Ploinky agents.

## Validation Plan

Run local static checks:

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

Use Podman instead of Docker if that is the configured local runtime.

Start through Ploinky:

```sh
cd /Users/danielsava/work/file-parser
ploinky start AchillesIDE/webmeetAgent
ploinky status
```

Smoke checks:

- Health port responds.
- LiveKit signaling responds.
- Redis is reachable internally.
- Coturn listens on the configured TCP/UDP ports.
- Egress starts and can connect to LiveKit and Redis.
- Prod Nginx and Certbot behavior remains explicit and profile-gated.
- WebMeet can create a room, establish media, and record if recording is part
  of the active profile.

Workflow validation:

- Confirm `.github/workflows/publish-livekit-server-agent.yml` parses.
- Confirm it uses `assistos` and `${{ secrets.DOCKERHUB_TOKEN }}` only.
- Do not dispatch the workflow unless the user explicitly asks.

## Risks And Open Questions

- The exact `livekit/egress` base image package manager and multi-arch support
  must be verified during implementation.
- A single container loses per-service Ploinky lifecycle and log visibility, so
  the supervisor must make failures obvious.
- Prod currently mixes host and bridge networking across separate agents. A
  single agent has one network namespace, so prod should probably use host
  networking and route internal dependencies through localhost.
- Egress privilege needs explicit verification. Do not assume the old
  `capabilities` field was enforced by Ploinky.
- The final Docker Hub repository name should be confirmed before dispatching
  the publish workflow.
