#!/usr/bin/env bash
# Run GCP CLI inside the 9ai-ext-google console image. Host gcloud is not required.
# Usage:
#   ./run.sh --help
#   ./run.sh gcloud auth list
#   ./run.sh /ext-google/gce/ssh-vps.sh vpnbox1 --dry-run
set -euo pipefail

EXT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${GCP_CONSOLE_IMAGE:-hahu-gcp-console:local}"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh --help
  ./run.sh [command ...]

Runs command in the 9ai-ext-google Docker console (gcloud, gsutil, bq).
Host gcloud is not required. Docker is required.

Credentials (first match):
  GCP_CREDENTIALS_JSON     minified service-account JSON
  GCP_CREDENTIALS_FILE     path to JSON (e.g. gcp.key.json)

Examples:
  GCP_CREDENTIALS_FILE=./sa.json ./run.sh gcloud auth list
  GCP_CREDENTIALS_FILE=./sa.json ./run.sh /ext-google/gce/ssh-vps.sh vpnbox1
  ./run.sh --help
EOF
}

die() {
  echo "Error: $*" >&2
  echo "  GCP_CREDENTIALS_FILE=./sa.json ./run.sh gcloud auth list" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

command -v docker >/dev/null || die "docker required for 9ai-ext-google console (no host gcloud)"

load_creds() {
  if [[ -n "${GCP_CREDENTIALS_JSON:-}" ]]; then
    return 0
  fi
  local f="${GCP_CREDENTIALS_FILE:-}"
  [[ -n "$f" && -f "$f" ]] || die "set GCP_CREDENTIALS_JSON or GCP_CREDENTIALS_FILE"
  GCP_CREDENTIALS_JSON="$(python3 -c 'import json,sys; p=sys.argv[1]; json.load(open(p)); print(open(p).read())' "$f")"
  export GCP_CREDENTIALS_JSON
}

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" "${EXT_ROOT}/console"
fi

load_creds

if [[ $# -eq 0 ]]; then
  set -- bash
fi

exec docker run --rm \
  -e GCP_CREDENTIALS_JSON \
  -e GCP_PROJECT \
  -e EXT_GOOGLE_IN_CONSOLE=1 \
  -e SSH_VPS_SKIP_WAIT \
  -e SSH_VPS_PUBKEY \
  -e CLOUDSDK_COMPUTE_ZONE \
  -e CLOUDSDK_COMPUTE_REGION \
  -v "${EXT_ROOT}:/ext-google" \
  -w /ext-google \
  "$IMAGE" \
  "$@"
