---
id: DS001
title: Coding Style
status: implemented
owner: webmeet-infra-team
summary: Defines documentation, manifest, hook, and validation style for webmeetInfra.
---

# DS001 - Coding Style

## Introduction

Defines documentation, manifest, hook, and validation style for webmeetInfra.

## Core Content

webmeetInfra changes are mostly manifests, generated runtime config templates, hook scripts, and documentation. JSON manifests use two-space indentation where the local file already does so, shell hooks must be POSIX-compatible unless a manifest explicitly chooses another shell, and documentation must be written in English.

New infrastructure agents must add a manifest, a focused DS file, matrix coverage, and local documentation in the same change. Generated or runtime-owned files such as LiveKit YAML and Redis data must not be treated as hand-authored secrets.

## Decisions & Questions

### Question #1: Why document this infrastructure service as a Ploinky agent?

Response:
Ploinky starts and routes these services through the same manifest and dependency graph used for application agents. Keeping the service contract in a DS file preserves runtime, port, secret, and dependency assumptions for future changes made from inside the infrastructure repository.

## Conclusion

Coding Style remains valid while its manifest, runtime configuration, and dependency behavior preserve the boundaries documented in this specification.
