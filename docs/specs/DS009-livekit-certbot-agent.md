---
id: DS009
title: LiveKit Certbot Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the Let's Encrypt cert renewal worker that pairs with the LiveKit Nginx agent.
---

# DS009 - LiveKit Certbot Agent

## Introduction

Documents the `webmeetLivekitCertbot` agent. It owns the Let's Encrypt cert lifecycle for the LiveKit signaling hostname through the ACME HTTP-01 challenge served by `webmeetLivekitNginx` (DS008). It replaces the previous host-system certbot timer so that cert renewal is part of the Ploinky agent lifecycle.

## Core Content

The agent runs `certbot/certbot:${WEBMEET_CERTBOT_VERSION}` with `entrypoint: "/bin/sh"` and a generated `start.sh`. The entrypoint override is required because the upstream image's default entrypoint is `["certbot"]`, which would interpret a script path as a CLI subcommand. The `entrypoint` manifest field is a Ploinky runtime feature documented in the Ploinky DS003 spec.

It runs with `network.mode: "host"`. The agent does not bind any ports of its own; host networking is used only because the ACME HTTP-01 challenge response file must be visible at the same `webroot` path that the nginx agent reads from. Both agents share that volume regardless of network mode. The manifest declares `readiness.protocol: "none"` so the Ploinky readiness gate treats the worker as immediately ready instead of probing a port the agent never binds (see Ploinky DS007).

The agent shares two volumes with `webmeetLivekitNginx` (DS008):

- `.ploinky/data/webmeetTls/letsencrypt` mounted at `/etc/letsencrypt` — write target for `certbot certonly` and `certbot renew`.
- `.ploinky/data/webmeetTls/webroot` mounted at `/var/www/certbot` — write target for HTTP-01 challenge tokens.

The renewal loop (generated `start.sh`) reads the following env vars:

- `WEBMEET_TLS_HOSTNAME` (required) — the cert's primary domain.
- `WEBMEET_CERT_EMAIL` (required when issuing a new cert) — Let's Encrypt account contact for ACME registration.
- `WEBMEET_CERTBOT_RENEW_INTERVAL_SECONDS` (default `43200` = 12h) — sleep between renew attempts. Renewals are no-ops outside the 30-day-from-expiry window, so a 12h cadence is safe and self-throttling.
- `WEBMEET_CERTBOT_AUTO_ISSUE` (default `false`) — when `true`, the agent will issue a new cert on first run if `/etc/letsencrypt/live/<host>/` is missing. When `false`, the agent only renews an already-issued cert. This flag is a guard against accidental ACME registration during initial cutovers; operators must explicitly opt in.

First-time issuance uses `--standalone` (certbot binds `:80` itself for the duration of the ACME HTTP-01 challenge), and renewals use `--webroot --webroot-path /var/www/certbot` once the nginx agent is running and answering on `:80`. This split avoids the bootstrap deadlock where the nginx agent waits for a cert that does not yet exist while certbot waits for nginx to serve the challenge — on first run, certbot owns `:80` briefly, issues the cert, exits standalone mode, and the nginx agent then starts and binds `:80` for renewal-time webroot challenges.

The agent does not push anything into the running nginx process. The nginx agent watches the cert file in the shared volume and runs `nginx -s reload` on rotation, which keeps the cross-container contract one-way: certbot writes, nginx reads.

## Decisions & Questions

### Question #1: Why is auto-issue gated behind a flag instead of always running on first start?

Response:
Initial cutover scenarios commonly already have a valid cert that lives in a host-system `/etc/letsencrypt`. Migrating that cert into the workspace volume is a one-time copy step rather than a fresh ACME registration. Defaulting auto-issue to `false` lets operators run the agent against an existing cert without registering a new ACME account, and forces an explicit decision before the agent talks to the Let's Encrypt CA on behalf of the workspace.

### Question #2: Why does the agent need to be a Ploinky agent at all instead of a host systemd timer?

Response:
The workspace invariant is that long-running services are Ploinky agents. Keeping certbot inside the agent lifecycle means cert renewal lives, ages, and gets observed alongside the rest of the WebMeet infrastructure (logs in `podman logs`, restart on deploy, version pinned by manifest var). It also avoids the split where Nginx is a Ploinky agent but the renewal that keeps it serving valid TLS lives in a separate host scheduler.

### Question #3: Why does the renew loop use HTTP-01 webroot rather than DNS-01?

Response:
HTTP-01 is the existing host-system contract for this hostname; switching to DNS-01 would require a Cloudflare API token in the workspace var store and additional checking around DNS propagation. HTTP-01 keeps the migration narrow and stays compatible with a single-cert single-domain setup. DNS-01 may become attractive later if wildcard certs or networks that block port 80 enter the requirements; that change must update both this spec and `WEBMEET_CERTBOT_AUTO_ISSUE` semantics together.

## Conclusion

The LiveKit Certbot Agent is the cert lifecycle owner for the LiveKit signaling hostname. It must keep the shared volumes with the nginx agent, the renew-loop semantics, and the explicit auto-issue gate documented here so that operator-facing cert behavior matches the workspace contract.
