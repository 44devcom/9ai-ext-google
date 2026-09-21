#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

usage() {
  cat <<'EOF'
Usage:
  tag.sh SOURCE DEST

Tag a local Docker image (host Docker daemon).

Examples:
  tag.sh my-app:local europe-west1-docker.pkg.dev/PROJECT/REPO/my-app:latest
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

require_arg "SOURCE" "${1:-}"
require_arg "DEST" "${2:-}"

docker tag "$1" "$2"
echo "Tagged $1 → $2" >&2
