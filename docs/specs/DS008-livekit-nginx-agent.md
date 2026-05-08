---
id: DS008
title: LiveKit Nginx Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the Nginx TLS terminator and reverse proxy in front of the LiveKit signaling endpoint.
---

# DS008 - LiveKit Nginx Agent

## Introduction

Documents the Nginx TLS terminator agent that fronts LiveKit signaling for `livekit-skills.axiologic.dev`. LiveKit Server 1.11 cannot terminate TLS on its main HTTP/WebSocket port (only `--turn-cert`/`--turn-key` exist for the TURN listener), so a TLS terminator is required on top of the host-network LiveKit. The Nginx agent replaces the previously host-system-managed Nginx instance with a Ploinky-managed one that fits the workspace invariant: every long-running service is a Ploinky agent.

## Core Content

The `webmeetLivekitNginx` agent owns TLS termination, ACME HTTP-01 challenge serving, and HTTP-to-HTTPS redirect for the LiveKit signaling hostname. It must run with `network.mode: "host"` so it binds the public-facing ports directly on the host's network namespace; with bridge networking, the agent could not own ports `80` and `443` cleanly while LiveKit also wants the host network namespace for media.

The container image is pinned through `WEBMEET_NGINX_VERSION` and the manifest expands `docker.io/library/nginx:${WEBMEET_NGINX_VERSION}`. The default tag is a current Alpine-based stable release; operators may bump it through the workspace var without editing the manifest.

The agent shares two volumes with `webmeetLivekitCertbot` (DS009):

- `.ploinky/data/webmeetTls/letsencrypt` mounted at `/etc/letsencrypt` (read by Nginx for cert and key files; written by certbot during issue and renewal).
- `.ploinky/data/webmeetTls/webroot` mounted at `/var/www/certbot` (read by Nginx to serve `/.well-known/acme-challenge/`; written by certbot during HTTP-01 challenge).

These volumes live inside the Ploinky workspace tree so the cert lifecycle is workspace-owned rather than host-owned. Migrating from a host-managed `/etc/letsencrypt` requires copying the existing cert directory tree into the workspace data path before the agent first starts; the cutover plan in the workspace handoff documents this step.

The preinstall hook generates two files:

- `.ploinky/agents/webmeetLivekitNginx/livekit.conf` mounted at `/etc/nginx/conf.d/default.conf` — declares one HTTP server (port from `WEBMEET_TLS_HTTP_PORT`) that serves the ACME challenge path and redirects everything else to HTTPS, and one HTTPS server (port from `WEBMEET_TLS_HTTPS_PORT`) that loads the cert from the shared volume and reverse-proxies `/` to `WEBMEET_LIVEKIT_UPSTREAM` with WebSocket upgrade headers and long read/send timeouts.
- `.ploinky/agents/webmeetLivekitNginx/start.sh` mounted at `/code/start.sh` — runs `nginx -g 'daemon off;'` plus a sidecar loop that polls the certificate file's hash every 60 seconds and runs `nginx -s reload` when the hash changes. Cross-container signaling is avoided so the certbot agent does not need a podman socket or shared signal mechanism.

The manifest declares profile-specific `ports` lists. With `network.mode: "host"` the runtime treats them as probe metadata only (DS007 in the Ploinky repo); they must match what Nginx actually binds, otherwise the readiness gate will fail with `ECONNREFUSED`. The `default` and `prod` profiles bind `80` and `443`. The `dev` profile binds `18080` and `18443` so a developer host can run the agent without conflicting with a host-system Nginx during a phased cutover.

## Decisions & Questions

### Question #1: Why does this agent run with host networking?

Response:
The publicly-reachable ports for LiveKit signaling must be `443` (and `80` for the ACME redirect). Bridge networking would force the agent into the same UDP-src-NAT regime described in DS003 for LiveKit and would also collide with LiveKit's host network namespace. Host networking gives the agent direct ownership of the host's port surface and matches the topology of the LiveKit peer it fronts.

### Question #2: Why is cert reload polled inside the Nginx container instead of signaled by the certbot agent?

Response:
A polling loop inside the same container that needs to reload keeps the contract self-contained: the certbot agent only writes files to the shared volume, and the nginx agent reacts. Cross-container signaling would require either a podman socket inside the certbot container or a shared FIFO with an unprivileged listener, both of which widen the trust surface for a one-line behavior. A 60-second poll is acceptable because cert rotations happen on the order of weeks, and a 60-second worst-case staleness window for the new cert is invisible to operators.

## Conclusion

The LiveKit Nginx Agent owns TLS termination and ACME challenge serving for the LiveKit signaling hostname. It must keep host networking, the shared TLS volumes, and the in-container cert-watch reload loop documented here so that the certbot agent and the cutover from host-system Nginx remain coherent.
