#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../scripts/img/_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/img/_common.sh"

# Always Free Cloud Build: e2-standard-2 (2,500 build-min/month).
MACHINE_TYPE="e2-standard-2"
DEFAULT_REGION="us-central1"

usage() {
  cat <<'EOF'
Usage:
  cloudbuild.sh [SOURCE] [--config PATH] [--tag IMAGE] [--region REGION]
                [--substitutions KEY=VAL,...] [--async]

Submit a Cloud Build job via the console container (Always Free machine).

SOURCE defaults to "." (must be under the monorepo root; remapped to /workspace).

Options:
  --config PATH           cloudbuild.yaml (or other config) path
  --tag IMAGE             Build Dockerfile in SOURCE and push IMAGE
                          (Artifact Registry repo + push IAM required)
  --region REGION         Regional Cloud Build (default: us-central1)
  --substitutions K=V,... Build substitutions
  --async                 Return after create; do not stream logs
  --help, -h              Show this help

Notes:
  Source is uploaded to a Cloud Storage staging bucket; the worker downloads
  it. Artifact Registry is only needed when using --tag.
  Free tier: 2,500 build-min/month on e2-standard-2 only.

Examples:
  cloudbuild.sh . --config path/to/cloudbuild.yaml
  cloudbuild.sh apps/foo --tag REGION-docker.pkg.dev/PROJECT/REPO/IMAGE:tag
EOF
}

# Resolve a host path and map it into the compose mount (/workspace = REPO_ROOT).
map_to_workspace() {
  local host_path="$1"
  local abs

  if [[ -d "$host_path" ]]; then
    abs="$(cd "$host_path" && pwd)"
  elif [[ -e "$host_path" ]]; then
    abs="$(cd "$(dirname "$host_path")" && pwd)/$(basename "$host_path")"
  else
    echo "error: path does not exist: $host_path" >&2
    exit 1
  fi

  case "$abs" in
    "$REPO_ROOT")
      printf '%s\n' "/workspace"
      ;;
    "$REPO_ROOT"/*)
      printf '%s\n' "/workspace/${abs#"$REPO_ROOT"/}"
      ;;
    *)
      echo "error: path must be under monorepo root ($REPO_ROOT): $host_path" >&2
      exit 1
      ;;
  esac
}

SOURCE=""
CONFIG=""
TAG=""
REGION="$DEFAULT_REGION"
SUBSTITUTIONS=""
ASYNC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --config)
      CONFIG="${2:-}"
      if [[ -z "$CONFIG" ]]; then
        echo "error: --config requires a PATH" >&2
        usage >&2
        exit 1
      fi
      shift 2
      ;;
    --config=*)
      CONFIG="${1#*=}"
      shift
      ;;
    --tag)
      TAG="${2:-}"
      if [[ -z "$TAG" ]]; then
        echo "error: --tag requires an IMAGE" >&2
        usage >&2
        exit 1
      fi
      shift 2
      ;;
    --tag=*)
      TAG="${1#*=}"
      shift
      ;;
    --region)
      REGION="${2:-}"
      if [[ -z "$REGION" ]]; then
        echo "error: --region requires a REGION" >&2
        usage >&2
        exit 1
      fi
      shift 2
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --substitutions)
      SUBSTITUTIONS="${2:-}"
      if [[ -z "$SUBSTITUTIONS" ]]; then
        echo "error: --substitutions requires KEY=VAL,..." >&2
        usage >&2
        exit 1
      fi
      shift 2
      ;;
    --substitutions=*)
      SUBSTITUTIONS="${1#*=}"
      shift
      ;;
    --async)
      ASYNC=1
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$SOURCE" ]]; then
        echo "error: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      SOURCE="$1"
      shift
      ;;
  esac
done

if [[ -z "$CONFIG" && -z "$TAG" ]]; then
  echo "error: require --config PATH and/or --tag IMAGE" >&2
  usage >&2
  exit 1
fi

SOURCE="${SOURCE:-.}"

ws_source="$(map_to_workspace "$SOURCE")"
args=(builds submit "$ws_source" "--machine-type=$MACHINE_TYPE")

if [[ -n "$CONFIG" ]]; then
  args+=(--config="$(map_to_workspace "$CONFIG")")
fi
if [[ -n "$TAG" ]]; then
  args+=(--tag="$TAG")
fi
args+=(--region="$REGION")
if [[ -n "$SUBSTITUTIONS" ]]; then
  args+=(--substitutions="$SUBSTITUTIONS")
fi
if [[ "$ASYNC" -eq 1 ]]; then
  args+=(--async)
fi

log="$(mktemp)"
set +e
run_gcp gcloud "${args[@]}" >"$log" 2>&1
rc=$?
set -e
cat "$log"
if [[ "$rc" -eq 0 ]]; then
  rm -f "$log"
  exit 0
fi
if cloudbuild_submit_denied "$log"; then
  export CLOUD_BUILD_REGION="$REGION"
  echo "cloudbuild: submit denied (serviceusage/bucket); granting and retrying" >&2
  grant_cloudbuild_submit_access "$log"
  rm -f "$log"
  sleep 8
  run_gcp gcloud "${args[@]}"
  exit $?
fi
rm -f "$log"
exit "$rc"
