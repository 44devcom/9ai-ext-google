#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

usage() {
  cat <<'EOF'
Usage:
  pull.sh IMAGE [--configure]

Pull an image with the host Docker daemon (after Artifact Registry auth).

Options:
  --configure   Run configure-docker.sh for the image's registry host first
  --help, -h    Show this help

Examples:
  pull.sh europe-west1-docker.pkg.dev/PROJECT/REPO/IMAGE:tag
  pull.sh europe-west1-docker.pkg.dev/PROJECT/REPO/IMAGE:tag --configure
EOF
}

CONFIGURE=0
IMAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --configure)
      CONFIGURE=1
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$IMAGE" ]]; then
        echo "error: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      IMAGE="$1"
      shift
      ;;
  esac
done

require_arg "IMAGE" "$IMAGE"

if [[ "$CONFIGURE" -eq 1 ]]; then
  host="${IMAGE%%/*}"
  "$CONSOLE_ROOT/scripts/img/configure-docker.sh" "$host"
fi

docker pull "$IMAGE"
