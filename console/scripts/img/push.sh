#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

usage() {
  cat <<'EOF'
Usage:
  push.sh IMAGE [--tag SOURCE] [--configure]

Push an image with the host Docker daemon (after Artifact Registry auth).

Options:
  --tag SOURCE  docker tag SOURCE IMAGE before push
  --configure   Run configure-docker.sh for the image's registry host first
  --help, -h    Show this help

Examples:
  push.sh europe-west1-docker.pkg.dev/PROJECT/REPO/IMAGE:tag
  push.sh europe-west1-docker.pkg.dev/PROJECT/REPO/IMAGE:tag --tag my-app:local
  push.sh europe-west1-docker.pkg.dev/PROJECT/REPO/IMAGE:tag --tag my-app:local --configure
EOF
}

CONFIGURE=0
IMAGE=""
TAG_SOURCE=""

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
    --tag)
      TAG_SOURCE="${2:-}"
      if [[ -z "$TAG_SOURCE" ]]; then
        echo "error: --tag requires a SOURCE image" >&2
        usage >&2
        exit 1
      fi
      shift 2
      ;;
    --tag=*)
      TAG_SOURCE="${1#*=}"
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

if [[ -n "$TAG_SOURCE" ]]; then
  docker tag "$TAG_SOURCE" "$IMAGE"
  echo "Tagged $TAG_SOURCE → $IMAGE" >&2
fi

docker push "$IMAGE"
