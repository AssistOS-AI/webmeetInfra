# webmeetInfra

Ploinky repository for the WebMeet media runtime.

The runtime is delivered by one Ploinky agent:

- `webmeetInfra/liveKitServerAgent` — see
  [`liveKitServerAgent/README.md`](liveKitServerAgent/README.md)

That agent runs a pinned multi-architecture image and supervises Redis,
LiveKit Server, LiveKit Egress, and private health. LiveKit signaling and Twirp
bind to loopback TCP `7880`; public signaling and private administrative calls
reach it only through the corresponding RoutingServer services. LiveKit owns
the box's single UDP mux on `7882`. Egress template `7980` and semantic health
`7981` are loopback-only and owner-checked. The runtime deliberately rejects
the upstream wildcard-health binary; release activation requires the published
multi-architecture digest from the commit-pinned loopback patch build.

TURN is external. Ploinky brokers short-lived relay credentials to authorized
current-generation consumers. This repository contains no relay daemon,
public TLS proxy, certificate process, tunnel connector, DNS automation, or
physical-host publication configuration.

The app-facing WebMeet agent remains in `AchillesIDE`; this repository owns
only the runtime services and their generated private configuration.
