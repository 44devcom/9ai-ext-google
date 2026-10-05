# GCP console (`packages/ext/google/console`)

Run `gcloud`, `gsutil`, and `bq` in Docker using a service account JSON.
Adapted from [44gcp](https://github.com/44devcom/44gcp) for this monorepo.

Also provides thin Artifact Registry helpers so host Docker can pull/push/tag
images after `gcloud auth configure-docker`.

## Prerequisites

- Docker and Docker Compose
- GCP service account material in the sealed vault (`vault material`, service
  `gcp`, name `default`) — projected as `GCP_CREDENTIALS_JSON`

## Setup

### Load from vault

`.env.example` is a name catalog only. Prefer vault material + projected export
over writing `gcp.json` or `.env`:

```bash
export CONFIG_PASSWORD='…'   # or --password-file
export VAULT_PATH=/path/to/vault.enc

# Store SA JSON once (if not already in vault):
# vault material set --vault "$VAULT_PATH" --service gcp --name default \
#   --format json --file /path/to/sa.json --password-env CONFIG_PASSWORD

cd packages/ext/google/console
set -a
eval "$(vault env export --vault "$VAULT_PATH" --service gcp_console --environment local \
  --project-credentials --password-env CONFIG_PASSWORD --format shell)"
set +a

docker compose build
```

Optional: set `GCP_PROJECT` to override `project_id` from the JSON.

Never commit `gcp.json`, `.env`, or exported credential values. Do not write
those files as the happy path.

## Usage

### Interactive shell

```bash
docker compose run --rm gcp
```

Inside the container the monorepo root is mounted at `/workspace`.

```bash
gcloud auth list
gcloud config get-value project
gsutil ls
```

### One-shot commands (no host gcloud)

```bash
GCP_CREDENTIALS_FILE=/path/to/sa.json ./run.sh gcloud auth list
GCP_CREDENTIALS_FILE=/path/to/sa.json ./run.sh /ext-google/gce/ssh-vps.sh vpnbox1
```

Host `gcloud` is not required. Docker is.

### One-shot commands (compose)

```bash
docker compose run --rm gcp gcloud auth list
docker compose run --rm gcp gcloud config get-value project
docker compose run --rm gcp gcloud storage ls
```

### Without Docker Compose

```bash
docker build -t hahu-gcp-console:local .
docker run --rm -it \
  -v "$(git rev-parse --show-toplevel)":/workspace \
  -e GCP_CREDENTIALS_JSON \
  hahu-gcp-console:local gcloud auth list
```

## Artifact Registry helpers

Auth: the console container prints an access token; helpers run host
`docker login` (no host `gcloud` / `docker-credential-gcloud` required).
Tokens expire (~1h)—re-run `configure-docker.sh` if auth starts failing.
Pull/push/tag use the **host** Docker daemon.

| Script | Purpose |
|--------|---------|
| [`scripts/img/configure-docker.sh`](scripts/img/configure-docker.sh) | `gcloud auth configure-docker` for a region/host |
| [`scripts/img/pull.sh`](scripts/img/pull.sh) | `docker pull` (optional `--configure`) |
| [`scripts/img/push.sh`](scripts/img/push.sh) | `docker push` (optional `--tag SOURCE`, `--configure`) |
| [`scripts/img/tag.sh`](scripts/img/tag.sh) | `docker tag SOURCE DEST` |

Example (after **Load from vault** so `GCP_CREDENTIALS_JSON` is in the environment):

```bash
./scripts/img/configure-docker.sh europe-west1
./scripts/img/pull.sh europe-west1-docker.pkg.dev/PROJECT/REPO/IMAGE:tag
./scripts/img/tag.sh my-app:local europe-west1-docker.pkg.dev/PROJECT/REPO/my-app:latest
./scripts/img/push.sh europe-west1-docker.pkg.dev/PROJECT/REPO/my-app:latest
```

IAM: Artifact Registry Reader for pull; Writer (or Admin) for push.

Helpers may still fall back to a leftover repo-root `gcp.json` when
`GCP_CREDENTIALS_JSON` is unset — that path is legacy, not the documented source
of truth.

## How authentication works

On startup, the entrypoint:

1. Uses `GCP_CREDENTIALS_JSON` if set; otherwise, on a TTY, prompts to paste JSON
2. Validates service account JSON
3. Writes `/secrets/gcp-key.json` inside the container
4. Sets `GOOGLE_APPLICATION_CREDENTIALS` and runs `gcloud auth activate-service-account`
5. Sets the default project from `GCP_PROJECT` or JSON `project_id`

## Security

- Prefer vault material + `vault env export --project-credentials`; never commit
  `.env` or service account key files.
- Credentials in env vars are visible via `docker inspect`.
- Use a dedicated least-privilege service account; rotate if leaked.

## Troubleshooting

**GCP_CREDENTIALS_JSON is not set**

Re-run **Load from vault** (`--service gcp_console --project-credentials`), or
paste JSON when running an interactive TTY session.

**Docker push/pull unauthorized**

Run `./scripts/img/configure-docker.sh <region>` and confirm the SA has
Artifact Registry permissions for that repository.
