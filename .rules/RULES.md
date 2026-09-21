# packages/ext/google — rules

Extends: `.project/.rules/`, `.project/packages/.rules/`, `.project/packages/ext/.rules/`

## GCP-001 — MUST ship only a vendor CLI console under EXT-004

This unit ships the GCP CLI console image under `console/` and no Python
distribution (`platform-google`) and no `@platform/google` kit. It is exempt
from the PKG-003 name triple under EXT-004.

Advisory: console-only unit; enforce via review.

## GCP-002 — MUST keep the compose file where callers resolve it by path

`console/docker-compose.yml` stays at that relative path so operators and
vault-projected runs (`core/vault`) can reach it via
`.project/packages/ext/google/console/docker-compose.yml`
(provider id `gcp` → folder `google`).

Advisory: compose path is the reachability contract; enforce via review.

## DOC-001 — MUST NOT cross-link or cross-write outside this unit in corpus files

Corpus files stay inside this unit.

Advisory: corpus stays unit-local; enforce via review / docs_scope_check.
