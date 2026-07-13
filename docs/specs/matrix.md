# Specification Matrix

Generated from DS frontmatter. Edit the DS files and rerun the matrix generator instead of editing this file manually.

| Specification | Title | Status | Owner | Summary |
| --- | --- | --- | --- | --- |
| [DS000](specsLoader.html?spec=DS000-vision.md) | WebMeet Infra Vision | [[status:implemented]] | webmeet-infra-team | Defines webmeetInfra as the Ploinky media-runtime repository delivered by liveKitServerAgent and turnServerAgent. |
| [DS001](specsLoader.html?spec=DS001-coding-style.md) | Coding Style | [[status:implemented]] | webmeet-infra-team | Defines documentation, manifest, hook, and validation style for webmeetInfra. |
| [DS002](specsLoader.html?spec=DS002-livekit-server-agent.md) | liveKitServerAgent | [[status:implemented]] | webmeet-infra-team | Single Ploinky agent that supervises Redis, LiveKit Server, and LiveKit Egress inside one container; TURN now lives in the sibling turnServerAgent. |
| [DS003](specsLoader.html?spec=DS003-ploinky-runtime-invariants.md) | Ploinky Runtime Invariants | [[status:implemented]] | webmeet-infra-team | Captures the Ploinky routing, authentication, guest, secure-wire, sandbox, and documentation invariants that must remain in local context when changing this agent. |
| [DS004](specsLoader.html?spec=DS004-turn-server-agent.md) | turnServerAgent | [[status:implemented]] | webmeet-infra-team | Single Ploinky agent that runs Coturn as the dedicated WebMeet TURN/STUN relay using shared-secret REST/ephemeral auth, with a fail-closed peer ACL and production TLS. |
