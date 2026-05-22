<!-- {"achilles-ide-document":{"id":"Ly5wbG9pbmt5L3JlcG9zL3dlYm1lZXRJbmZyYS9kb2NzL3NwZWNzL0RTMDAwLXZpc2lvbi5tZA==","title":"DS000-vision","version":1,"updatedAt":"2026-05-08T14:58:59.098Z"}} -->
<!-- {"achilles-ide-chapter":{"id":"chapter-8d168ecc-51fb-4b23-a027-bc48f8ac7c69","title":"Chapter 1","anchorId":"chapter-chapter-8d168ecc-51fb-4b23-a027-bc48f8ac7c69"}} -->
<a id="chapter-chapter-8d168ecc-51fb-4b23-a027-bc48f8ac7c69"></a>
## Chapter 1
<!-- {"achilles-ide-paragraph":{"id":"paragraph-2cea0004-f29c-478a-85e0-17c3928fc237","type":"markdown","title":"Paragraph 1"}} -->
---
id: DS000
title: WebMeet Infra Vision
status: implemented
owner: webmeet-infra-team
summary: Defines webmeetInfra as the Ploinky repository whose runtime is delivered by the single liveKitServerAgent.
---


<!-- {"achilles-ide-chapter":{"id":"chapter-0ca12978-77db-4b35-b08c-74d1ff8107d1","title":"DS000 - WebMeet Infra Vision","anchorId":"chapter-chapter-0ca12978-77db-4b35-b08c-74d1ff8107d1"}} -->
<a id="chapter-chapter-0ca12978-77db-4b35-b08c-74d1ff8107d1"></a>
# DS000 - WebMeet Infra Vision
<!-- {"achilles-ide-paragraph":{"id":"paragraph-b3a534c6-04fa-47c1-a517-5a2647d9a8a1","type":"markdown","title":"Paragraph 1"}} -->


<!-- {"achilles-ide-chapter":{"id":"chapter-f62db1df-df79-483b-b869-c7894c1ab0d4","title":"Introduction","anchorId":"chapter-chapter-f62db1df-df79-483b-b869-c7894c1ab0d4"}} -->
<a id="chapter-chapter-f62db1df-df79-483b-b869-c7894c1ab0d4"></a>
## Introduction
<!-- {"achilles-ide-paragraph":{"id":"paragraph-5c738fe4-20de-4723-8b18-9814d58d95c2","type":"markdown","title":"Paragraph 1"}} -->
webmeetInfra is the Ploinky repository that owns the WebMeet media runtime. The runtime is delivered by one Ploinky agent, `liveKitServerAgent`, which supervises Redis, Coturn, LiveKit Server, LiveKit Egress, and (in the `prod` profile) the Nginx TLS terminator plus a Certbot renewal loop inside one container.


<!-- {"achilles-ide-chapter":{"id":"chapter-aaf44b47-7186-4ae2-b9b1-752b68609843","title":"Core Content","anchorId":"chapter-chapter-aaf44b47-7186-4ae2-b9b1-752b68609843"}} -->
<a id="chapter-chapter-aaf44b47-7186-4ae2-b9b1-752b68609843"></a>
## Core Content
<!-- {"achilles-ide-paragraph":{"id":"paragraph-7cff1830-24f5-4a71-9a27-512a255fa12a","type":"markdown","title":"Paragraph 1"}} -->
webmeetInfra must remain an infrastructure repository. It owns Redis, TURN/STUN, LiveKit Server, LiveKit Egress, the Nginx TLS terminator, and the Certbot renewal loop, all supervised by `liveKitServerAgent` inside one container. It must not own WebMeet room business logic, guest invite validation, Explorer UI behavior, or meeting artifact policy. Those contracts belong to `webmeetAgent`.

The runtime image is published to Docker Hub as `assistos/livekit-server-agent:webmeet-infra` through a manual `workflow_dispatch` GitHub Actions workflow. Publishing requires the `DOCKERHUB_TOKEN` repository secret; token values are never committed to this repo.


<!-- {"achilles-ide-chapter":{"id":"chapter-5674c374-0ab2-4f02-a942-5ae094261751","title":"Decisions & Questions","anchorId":"chapter-chapter-5674c374-0ab2-4f02-a942-5ae094261751"}} -->
<a id="chapter-chapter-5674c374-0ab2-4f02-a942-5ae094261751"></a>
## Decisions & Questions
<!-- {"achilles-ide-paragraph":{"id":"paragraph-ca2d8307-0313-468d-a38b-6544013e61de","type":"markdown","title":"Paragraph 1"}} -->


<!-- {"achilles-ide-chapter":{"id":"chapter-ed1b4273-8c2d-4a76-884f-0fdb8a01c901","title":"Question #1: Why document this infrastructure service as a Ploinky agent?","anchorId":"chapter-chapter-ed1b4273-8c2d-4a76-884f-0fdb8a01c901"}} -->
<a id="chapter-chapter-ed1b4273-8c2d-4a76-884f-0fdb8a01c901"></a>
### Question #1: Why document this infrastructure service as a Ploinky agent?
<!-- {"achilles-ide-paragraph":{"id":"paragraph-19415be5-c337-4542-830f-a1d071d468cc","type":"markdown","title":"Paragraph 1"}} -->
Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.


<!-- {"achilles-ide-chapter":{"id":"chapter-8147a905-570f-452a-bc79-8cecd28233b5","title":"Conclusion","anchorId":"chapter-chapter-8147a905-570f-452a-bc79-8cecd28233b5"}} -->
<a id="chapter-chapter-8147a905-570f-452a-bc79-8cecd28233b5"></a>
## Conclusion
<!-- {"achilles-ide-paragraph":{"id":"paragraph-b2d2ddc5-9da3-4aea-9ab9-44b2c77d4b7f","type":"markdown","title":"Paragraph 1"}} -->
WebMeet Infra Vision remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.

