# liveKitServerAgent

Pinned runtime-v5 media infrastructure for WebMeet.

The agent supervises Redis, LiveKit Server, LiveKit Egress, and private health.
Configuration is generated from the Ploinky schema-v2 topology snapshot:
LiveKit signaling/API bind to `127.0.0.1:7880`, the advertised node address is
the configured literal globally routable unicast public IPv4, and LiveKit alone
owns UDP `7882`. Egress uses
loopback template/service `7980` and loopback semantic health `7981`.

Public WebSocket signaling is declared as `livekit-signal` and reaches loopback
LiveKit through Router. Administrative Twirp is declared as `livekit-api` and
is reachable only through private Router with current policy and caller
assertion. Public policy admits the LiveKit GET/WebSocket signaling flow and
rejects a crafted public Twirp `POST` before target selection or dial. Neither
service creates an outer publication.

External TURN is required for relay fallback. Ploinky brokers short-lived
credentials to allowed consumers; no long-term relay secret enters this agent.

The supervisor verifies exact Egress ownership, rejects wildcard copies of
either Egress listener, and semantically distinguishes health JSON from the
template application. Upstream Egress v1.9.1 is rejected because it binds
`7981` to wildcard; activation requires the separately published, source-pinned
loopback patch image and its resulting multi-architecture digest. Detailed
supervisor health is available only on
`/run/ploinky/livekit-supervisor.sock`.

Validation:

```bash
sh -n scripts/hooks/preinstall.sh
sh -n scripts/start-livekit-server-agent.sh
sh -n scripts/health/livekit-server-agent-health.sh
node --check scripts/health/supervisor-health.mjs
node --test tests/*.test.mjs
```
