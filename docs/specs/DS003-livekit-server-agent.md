---
id: DS003
title: LiveKit Server Agent
status: implemented
owner: webmeet-infra-team
summary: Documents the LiveKit SFU agent used by WebMeet room media.
---

# DS003 - LiveKit Server Agent

## Introduction

Documents the LiveKit SFU agent used by WebMeet room media.

## Core Content

The `webmeetLivekitServer` agent owns the LiveKit SFU runtime. Its manifest must keep API key and secret values in environment configuration and generated runtime config, not in browser assets or public docs.

LiveKit signaling and media ports are network-sensitive surfaces. Local development may expose them on localhost-style ports, while production review must treat any non-local binding as an operator network-security decision.

`WEBMEET_LIVEKIT_API_KEY` and `WEBMEET_LIVEKIT_API_SECRET` are workspace-owned agent secrets and must be derived from `PLOINKY_DERIVED_MASTER_KEY` through manifest `derive: "derived-master"` entries. These values must use the shared LiveKit derivation identity so `webmeetAgent`, LiveKit server, and egress all agree on the same credentials. Production startup must fail closed only if derived values cannot be produced; no profile may generate `livekit.yaml` with hard-coded development credentials.

The optional `WEBMEET_LIVEKIT_LOG_LEVEL` setting controls the generated LiveKit `logging.level` value and defaults to `info`. Operators may raise it for short diagnostic windows, but generated config and logs must still keep API keys, secrets, tokens, SDP payloads, and credentials out of persisted diagnostics.

The optional `WEBMEET_LIVEKIT_FORCE_TCP` setting controls LiveKit `rtc.force_tcp` and defaults to `false`. Production operators may enable it when the host or client network path drops UDP media packets while TCP signaling remains healthy. With the production network mode below, UDP media is the proven path; `WEBMEET_LIVEKIT_FORCE_TCP=true` remains the documented immediate rollback knob.

The generated LiveKit config is written on the host under `.ploinky/agents/webmeetLivekitServer/livekit.yaml` and mounted in the container at `/working-data/generated/livekit.yaml`. Generated runtime inputs must stay out of `/code` unless an upstream image requires them there; LiveKit is launched with `--config /working-data/generated/livekit.yaml`.

The container image is pinned through `WEBMEET_LIVEKIT_VERSION`. The manifest references `docker.io/livekit/livekit-server:${WEBMEET_LIVEKIT_VERSION}` and declares the variable in each profile with a default tag. Operators may override the default through the workspace var or the deploy workflow input. The manifest must not reference `:latest` directly, because image churn under a floating tag breaks the version-pinning invariant relied on for reproducible deploys and rollbacks.

The agent's network namespace is selected per profile. The `prod` profile declares `network.mode: "host"` so LiveKit binds `7880/tcp` (signaling), `7881/tcp` (TCP media), and `7882-7892/udp` (UDP media) directly on the host's network namespace; under that mode the `ports` lists are probe metadata for the Ploinky readiness gate, not bridge port-publishes, and the runtime strips `-p` emission. Host networking is required in production because podman bridge UDP port-publishing rewrites the inbound source address to a bridge-local IP, which causes the SFU's server-initiated SRTP downlink to be routed inside the bridge subnet and dropped before reaching the real client. The `default` and `dev` profiles declare `network.name: "webmeet"` (with alias `webmeetLivekitServer`) and use the standard Ploinky bridge port-publishing path, because non-Linux developer hosts (notably macOS, where podman runs inside a VM) cannot expose host-network container ports to the workstation and would never satisfy the readiness probe in host mode; for single-machine development the UDP/SRC-NAT failure mode does not apply.

`WEBMEET_LIVEKIT_REDIS_ADDRESS` is the LiveKit Redis address written into `redis.address` of the generated `livekit.yaml`. The profile defaults reflect how LiveKit reaches Redis on each topology: the `default` and `dev` profiles default to `webmeetRedis:6379` (LiveKit and Redis share the `webmeet` bridge network, so Redis is addressable by its alias); the `prod` profile leaves the value unset so the preinstall hook falls back to `127.0.0.1:6379`, where the host-network LiveKit consumes Redis through Redis's published `0.0.0.0:6379` host port. Operators may override the value per workspace if the Redis topology changes.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

### Question #2: Why does the LiveKit agent require host networking instead of bridge networking?

Response:
With bridge networking and `0.0.0.0:7882-7892:7882-7892/udp` published, podman's UDP port-forwarding path rewrites the inbound source IP to a bridge-internal address (observed as `prflx 10.89.0.x` in browser ICE stats during diagnostics). LiveKit's ICE library then learns the remote peer at that bridge IP and sends server-initiated SRTP downlink to it, where the kernel routes the packet inside the bridge subnet instead of out through the host's external interface. Receivers see no media. Host networking puts LiveKit directly in the host's network namespace, so it observes real client addresses and can reach them on its server-initiated send path. ICE/STUN keepalives and publisher uplink RTCP survived the bridge mode because they ride conntrack reversal; only the server-initiated UDP downlink failed. This is why `prod` keeps `network.mode: "host"`.

### Question #3: Why do `default` and `dev` not also use host networking?

Response:
Host networking is the production fix for a multi-client SRTP downlink failure mode; on a single-machine developer setup the failure mode does not appear, and the platforms developers use are often incompatible with `--network host` (notably macOS, where podman runs inside a VM and `--network host` joins the VM's namespace rather than the workstation's, so the readiness probe and a local browser cannot reach the listening ports). Putting `default` and `dev` on the shared `webmeet` bridge with explicit port publishing keeps the agent reachable from the workspace and from sibling agents through `webmeetLivekitServer:7880`, satisfies the readiness probe, and lets a developer run the agent on macOS or Linux without environment-specific manifest forks. Per-profile `network` (supported by Ploinky DS003) keeps the production topology unchanged.

### Question #4: Why is the container tag templated through `WEBMEET_LIVEKIT_VERSION` instead of pinned literally in the manifest?

Response:
Operators tune the deployed LiveKit version through the workspace var and the deploy workflow input, not by editing a manifest in the infrastructure repository. The Ploinky manifest contract supports `${VAR}` expansion in the `container` field for exactly this reason. Keeping the literal tag out of the manifest also avoids merge churn when the version is bumped and forces operators to set a value rather than silently inheriting `:latest`.

## Conclusion

LiveKit Server Agent remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
