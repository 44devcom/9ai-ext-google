# packages/ext/google — contract

## Provides
GCP CLI console image (`gcloud`, `gsutil`, `bq`) and compose service for
interactive and one-shot vendor CLI runs, plus host Docker Artifact Registry
helper scripts under `console/scripts/`. No Python distribution and no
`@platform/*` kit.

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
service name `gcp`.

## Change policy
Stable: everything above. May change without notice: Dockerfile base tags,
entrypoint wording, Artifact Registry helper script internals, console README
examples.
