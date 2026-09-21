# Changelog

History for `.project/packages/ext/google` (console-only; no Python distribution).

Daily work goes under `[Unreleased]`. A workspace release requires that section to have no list items. Promote it to a new `MAJOR.MINOR.PATCH` heading when this unit ships.

Do not recap other units here.

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.0] - 2026-09-21

### Changed

- `cloudbuild.sh` grants the operator SA `serviceusage.serviceUsageConsumer`,
  Cloud Build editor, and staging-bucket objectAdmin **when the same
  `gcloud builds submit` denial appears**, then retries once. If the staging bucket is missing it is created.
  Not a one-time initialize step.

- `free_tier/initialize.sh` also grants the operator / Compute SA
  `roles/serviceusage.serviceUsageConsumer`, `roles/cloudbuild.builds.editor`,
  and `roles/storage.objectAdmin`, plus objectAdmin on the Cloud Build
  staging bucket. That is the `serviceusage.services.use` / bucket-forbidden
  submit failure.

- GCP-002: compose path reachability is for operators / `core/vault`
  projection (no retired cloud backend package).

### Added

- Unit `.rules/RULES.md` / `.rules/CONTRACT.md`, root README, and changelog
  for the console-only GCP façade (EXT-004).

### Deprecated

### Removed

### Fixed

### Security
