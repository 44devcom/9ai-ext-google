# Changelog

History for `.project/packages/ext/google` (console-only; no Python distribution).

Daily work goes under `[Unreleased]`. A workspace release requires that section to have no list items. Promote it to a new `MAJOR.MINOR.PATCH` heading when this unit ships.

Do not recap other units here.

## [Unreleased]

### Changed

- `gce/iam.sh ensure-owner-sa` succeeds when org policy blocks service account
  keys: grants `roles/iam.serviceAccountTokenCreator` to the active principal
  and prints `gcloud` impersonation instructions instead of failing bootstrap.
- `gce_ensure_instance` create path disables shielded vTPM and Integrity
  Monitoring (`--no-shielded-vtpm`, `--no-shielded-integrity-monitoring`).
- GCP-002: compose path reachability is for operators / `core/vault`
  projection (no retired cloud backend package).

### Added

- `gce/ssh-vps.sh` create/reuse Debian GCE VM + static IP + TCP 22 (optional
  `--extra-ports`, `--ssh-pubkey`). No startup-script. If host has no
  `gcloud`, wraps `console/run.sh` (Docker console). Tests: `gce/test-ssh-vps.sh`.
- `console/run.sh` one-shot GCP CLI in `hahu-gcp-console:local`. Host gcloud
  is not required. Tests: `console/test-run.sh`.

- Open in Cloud Shell opens workspace `gce`, which auto-runs
  `gce/cloudshell-bootstrap.sh` via `.vscode/tasks.json` `folderOpen`.
- Open in Cloud Shell button (workspace `gce`) on root README and
  `gce/README.md`.
- `gce/iam.sh` to enable APIs, create/reuse `nineai-remote-owner` service
  account, grant `roles/owner`, and write a gitignored key JSON for remote
  `gcloud` manage (`ensure-owner-sa`, `show`, `grant-owner`, `enable-apis`).
- `gce/lib.sh` idempotent GCE ensure/delete helpers for Cloud Shell deploy
  callers (`gce_ensure_network`, `gce_ensure_address`, `gce_ensure_firewall`,
  `gce_ensure_instance`, matching `gce_delete_*`).
- Unit `.rules/RULES.md` / `.rules/CONTRACT.md`, root README, and changelog
  for the console-only GCP façade (EXT-004).

### Deprecated

### Removed

### Fixed

- Owner SA id is `nineai-remote-owner` (GCP rejects ids that start with a
  digit, so `9ai-remote-owner` never created and no key JSON was written).

### Security
