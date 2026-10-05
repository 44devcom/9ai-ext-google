# packages/ext/google — contract

## Provides
GCP CLI console image (`gcloud`, `gsutil`, `bq`) and compose service for
interactive and one-shot vendor CLI runs, plus host Docker Artifact Registry
helper scripts under `console/scripts/`, plus idempotent GCE ensure/delete
helpers under `gce/lib.sh` for Cloud Shell / operator deploy scripts, plus
`gce/iam.sh` to create/reuse a project Owner service account and key for
remote management, plus Cloud Shell surfaces `gce/tutorial.md`,
`gce/cloudshell-bootstrap.sh`, and `gce/cloudshell-print.txt`. No Python
distribution and no `@platform/*` kit.

## Inputs / assumptions
Callers supply GCP service-account material as environment credentials
(`GCP_CREDENTIALS_JSON`, optional `GCP_PROJECT`). Prefer vault projection
over writing `gcp.json` or `.env`. Docker and Docker Compose are required to
build and run the image.

## Extension points
None: this unit ships one vendor CLI console image and helper scripts only.

## Stable references
Compose file path `console/docker-compose.yml` (repo-relative
`.project/packages/ext/google/console/docker-compose.yml`). Image name
`hahu-gcp-console:local`. Renaming either is a breaking change. Compose
service name `gcp`. GCE library path `gce/lib.sh` and function names
`gce_ensure_*` / `gce_delete_*` are a breaking-change surface for deploy
callers (for example 9ai-network). `gce/iam.sh` subcommands
`ensure-owner-sa`, `show`, `grant-owner`, `enable-apis` are a
breaking-change surface for operators. Paths `gce/tutorial.md`,
`gce/cloudshell-bootstrap.sh`, and `gce/cloudshell-print.txt` are stable
Open in Cloud Shell surfaces.

## Change policy
Stable: everything above. May change without notice: Dockerfile base tags,
entrypoint wording, Artifact Registry helper script internals, console README
examples.
