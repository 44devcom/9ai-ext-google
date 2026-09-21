#!/usr/bin/env bash
# One-time (idempotent) project setup for free_tier compute + Cloud Build.
set -euo pipefail

# shellcheck source=../scripts/img/_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/img/_common.sh"

DEFAULT_REGION="us-central1"

APIS=(
  cloudbuild.googleapis.com
  compute.googleapis.com
  storage.googleapis.com
  logging.googleapis.com
  artifactregistry.googleapis.com
)

# Cloud Build service agent (staging bucket, build orchestration).
CLOUDBUILD_SA_ROLES=(
  roles/cloudbuild.builds.builder
  roles/storage.admin
)

# Default Compute Engine SA runs regional Cloud Build workers on many projects.
COMPUTE_SA_ROLES=(
  roles/storage.objectViewer
  roles/logging.logWriter
  roles/artifactregistry.writer
)

# Operator that runs `gcloud builds submit` (often the same Compute SA stored
# in .storage/google/gcp.json). Missing these is the
# "forbidden from accessing the bucket … serviceusage.services.use" error.
SUBMITTER_SA_ROLES=(
  roles/serviceusage.serviceUsageConsumer
  roles/cloudbuild.builds.editor
  roles/storage.objectAdmin
)

usage() {
  cat <<'EOF'
Usage:
  initialize.sh [--region REGION] [--skip-apis] [--skip-iam] [--skip-bucket]

Enable APIs and IAM needed for free_tier scripts (compute.sh, cloudbuild.sh).

Requires a credential that can enable services and set project IAM
(typically Owner or roles/owner on the billing project).

Options:
  --region REGION   Cloud Build staging bucket location (default: us-central1)
  --skip-apis       Skip gcloud services enable
  --skip-iam        Skip IAM policy bindings
  --skip-bucket     Skip gs://PROJECT_ID_cloudbuild bucket check/create
  --help, -h        Show this help

Reads project from GCP_PROJECT or gcloud config (via console/.env credentials).

Sets:
  APIs: Cloud Build, Compute, Storage, Logging, Artifact Registry
  IAM on PROJECT_NUMBER@cloudbuild.gserviceaccount.com:
    cloudbuild.builds.builder, storage.admin
  IAM on PROJECT_NUMBER-compute@developer.gserviceaccount.com:
    storage.objectViewer, logging.logWriter, artifactregistry.writer
    plus submitter roles: serviceusage.serviceUsageConsumer,
    cloudbuild.builds.editor, storage.objectAdmin
  IAM on the operator SA from GCP_CREDENTIALS_JSON (if different):
    the same submitter roles
  Staging bucket: gs://PROJECT_ID_cloudbuild (if missing) + objectAdmin
    for the operator / compute SA
EOF
}

REGION="$DEFAULT_REGION"
SKIP_APIS=0
SKIP_IAM=0
SKIP_BUCKET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --region)
      REGION="${2:-}"
      if [[ -z "$REGION" ]]; then
        echo "error: --region requires a REGION" >&2
        exit 1
      fi
      shift 2
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --skip-apis)
      SKIP_APIS=1
      shift
      ;;
    --skip-iam)
      SKIP_IAM=1
      shift
      ;;
    --skip-bucket)
      SKIP_BUCKET=1
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      echo "error: unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

project_id() {
  if [[ -n "${GCP_PROJECT:-}" ]]; then
    printf '%s\n' "$GCP_PROJECT"
    return 0
  fi
  run_gcp gcloud config get-value project 2>/dev/null
}

has_iam_binding() {
  local project="$1"
  local member="$2"
  local role="$3"
  run_gcp gcloud projects get-iam-policy "$project" \
    --flatten='bindings[].members' \
    --filter="bindings.members:$member AND bindings.role:$role" \
    --format='value(bindings.role)' 2>/dev/null | grep -qxF "$role"
}

bind_iam() {
  local project="$1"
  local member="$2"
  local role="$3"

  if has_iam_binding "$project" "$member" "$role"; then
    echo "iam: $member already has $role"
    return 0
  fi

  echo "iam: granting $role to $member"
  run_gcp gcloud projects add-iam-policy-binding "$project" \
    --member="$member" \
    --role="$role" \
    --condition=None \
    --quiet
}

operator_member() {
  python3 -c '
import json, os, sys
raw = os.environ.get("GCP_CREDENTIALS_JSON") or ""
if not raw:
    sys.exit(1)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(1)
email = str(data.get("client_email") or "").strip()
if not email:
    sys.exit(1)
print("serviceAccount:" + email)
'
}

bind_submitter_roles() {
  local project="$1"
  local member="$2"
  echo "configuring Cloud Build submitter IAM for $member..."
  for role in "${SUBMITTER_SA_ROLES[@]}"; do
    bind_iam "$project" "$member" "$role"
  done
}

grant_bucket_object_admin() {
  local bucket="$1"
  local member="$2"
  local email="${member#serviceAccount:}"
  echo "bucket iam: objectAdmin on gs://${bucket} for $email"
  run_gcp gsutil iam ch "serviceAccount:${email}:objectAdmin" "gs://${bucket}" || \
    run_gcp gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
      --member="$member" \
      --role="roles/storage.objectAdmin" \
      --quiet
}

ensure_credentials
PROJECT="$(project_id)"
if [[ -z "$PROJECT" ]]; then
  echo "error: could not resolve GCP project (set GCP_PROJECT or gcloud config)" >&2
  exit 1
fi

echo "project: $PROJECT"

PROJECT_NUMBER="$(run_gcp gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
if [[ -z "$PROJECT_NUMBER" ]]; then
  echo "error: could not resolve project number for $PROJECT" >&2
  exit 1
fi

echo "project_number: $PROJECT_NUMBER"

CLOUDBUILD_SA="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

if [[ "$SKIP_APIS" -eq 0 ]]; then
  echo "enabling APIs..."
  run_gcp gcloud services enable "${APIS[@]}" --project="$PROJECT"
else
  echo "skipping API enable"
fi

if [[ "$SKIP_IAM" -eq 0 ]]; then
  echo "configuring Cloud Build service account IAM..."
  for role in "${CLOUDBUILD_SA_ROLES[@]}"; do
    bind_iam "$PROJECT" "$CLOUDBUILD_SA" "$role"
  done

  echo "configuring default Compute Engine service account IAM (Cloud Build worker)..."
  for role in "${COMPUTE_SA_ROLES[@]}"; do
    bind_iam "$PROJECT" "$COMPUTE_SA" "$role"
  done

  bind_submitter_roles "$PROJECT" "$COMPUTE_SA"
  OPERATOR_SA="$(operator_member || true)"
  if [[ -n "${OPERATOR_SA:-}" && "$OPERATOR_SA" != "$COMPUTE_SA" ]]; then
    bind_submitter_roles "$PROJECT" "$OPERATOR_SA"
  fi
else
  echo "skipping IAM bindings"
fi

if [[ "$SKIP_BUCKET" -eq 0 ]]; then
  BUCKET="${PROJECT}_cloudbuild"
  echo "checking staging bucket gs://${BUCKET}..."
  if run_gcp gsutil ls -b "gs://${BUCKET}" >/dev/null 2>&1; then
    echo "bucket: gs://${BUCKET} exists"
  else
    echo "bucket: creating gs://${BUCKET} in ${REGION}"
    run_gcp gsutil mb -p "$PROJECT" -l "$REGION" "gs://${BUCKET}"
  fi
  grant_bucket_object_admin "$BUCKET" "$COMPUTE_SA"
  OPERATOR_SA="$(operator_member || true)"
  if [[ -n "${OPERATOR_SA:-}" && "$OPERATOR_SA" != "$COMPUTE_SA" ]]; then
    grant_bucket_object_admin "$BUCKET" "$OPERATOR_SA"
  fi
else
  echo "skipping staging bucket"
fi

cat <<EOF

done.

Next:
  free_tier/compute.sh          # e2-micro VM (Always Free US regions)
  free_tier/cloudbuild.sh ...   # Cloud Build submit (e2-standard-2)
  car24/scripts/cloudbuild-test.sh api

Cloud Build configs use logging: LEGACY and DOCKER_BUILDKIT=1 (see car24/cloudbuild*.yaml).
EOF
