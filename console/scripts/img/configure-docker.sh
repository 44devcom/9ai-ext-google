#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

usage() {
  cat <<'EOF'
Usage:
  configure-docker.sh [REGION|HOST ...]

Obtain an access token via the GCP console container and run
`docker login` on the host for Artifact Registry (no host gcloud SDK required).

Arguments:
  REGION or HOST   Region (e.g. europe-west1) or full host
                   (e.g. europe-west1-docker.pkg.dev).
                   Default: europe-west1 → europe-west1-docker.pkg.dev
                   Also accepts gcr.io / REGION-docker.pkg.dev forms.

Examples:
  configure-docker.sh
  configure-docker.sh europe-west1
  configure-docker.sh us-central1-docker.pkg.dev gcr.io

Requires Artifact Registry Reader (pull) or Writer (push) on the SA.
Tokens expire (~1h); re-run this script when pulls/pushes start failing auth.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

hosts=()
if [[ $# -eq 0 ]]; then
  hosts+=("europe-west1-docker.pkg.dev")
else
  for arg in "$@"; do
    if [[ "$arg" == *.* ]]; then
      hosts+=("$arg")
    else
      hosts+=("${arg}-docker.pkg.dev")
    fi
  done
fi

token="$(run_gcp gcloud auth print-access-token)"
if [[ -z "$token" ]]; then
  echo "error: failed to obtain access token" >&2
  exit 1
fi

for host in "${hosts[@]}"; do
  printf '%s' "$token" | docker login -u oauth2accesstoken --password-stdin "https://${host}"
  echo "Logged in host Docker to: ${host}" >&2
done
