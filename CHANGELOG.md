# Changelog

History for `.project/packages/ext/google` (console-only; no Python distribution).

Daily work goes under `[Unreleased]`. A workspace release requires that section to have no list items. Promote it to a new `MAJOR.MINOR.PATCH` heading when this unit ships.

Do not recap other units here.

## [Unreleased]

### Changed

- `gce_ensure_instance` create path disables shielded vTPM and Integrity
  Monitoring (`--no-shielded-vtpm`, `--no-shielded-integrity-monitoring`).
- GCP-002: compose path reachability is for operators / `core/vault`
  projection (no retired cloud backend package).

### Added

- `gce/lib.sh` idempotent GCE ensure/delete helpers for Cloud Shell deploy
  callers (`gce_ensure_network`, `gce_ensure_address`, `gce_ensure_firewall`,
  `gce_ensure_instance`, matching `gce_delete_*`).
- Unit `.rules/RULES.md` / `.rules/CONTRACT.md`, root README, and changelog
  for the console-only GCP façade (EXT-004).

### Deprecated

### Removed

### Fixed

### Security
