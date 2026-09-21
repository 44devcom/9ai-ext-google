#!/usr/bin/env bash
# Shared helpers for Artifact Registry scripts. Sourced, not executed.

set -euo pipefail

CONSOLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$CONSOLE_ROOT/../../../../.." && pwd)"
COMPOSE_FILE="$CONSOLE_ROOT/docker-compose.yml"
STORAGE_CREDS="$REPO_ROOT/.storage/google/gcp.json"
DEFAULT_CREDS="$REPO_ROOT/gcp.json"

credentials_json_valid() {
  [[ -n "${GCP_CREDENTIALS_JSON:-}" ]] || return 1
  python3 -c '
import json, os, sys
raw = os.environ["GCP_CREDENTIALS_JSON"]
for candidate in (raw, raw.encode().decode("unicode_escape")):
    try:
        json.loads(candidate)
        sys.exit(0)
    except json.JSONDecodeError:
        continue
sys.exit(1)
' >/dev/null 2>&1
}

load_console_dotenv() {
  local env_file="$CONSOLE_ROOT/.env"
  [[ -f "$env_file" ]] || return 1
  [[ -z "${GCP_CREDENTIALS_JSON:-}" ]] || return 0

  local exported
  if ! exported="$(
    python3 - "$env_file" <<'PY'
import json
import sys
from pathlib import Path

env = Path(sys.argv[1])
for line in env.read_text().splitlines():
    if not line.startswith("GCP_CREDENTIALS_JSON="):
        continue
    val = line.split("=", 1)[1].strip()
    if (val.startswith('"') and val.endswith('"')) or (
        val.startswith("'") and val.endswith("'")
    ):
        val = val[1:-1]
    for candidate in (val, val.encode().decode("unicode_escape")):
        try:
            data = json.loads(candidate)
            print(json.dumps(data, separators=(",", ":")))
            sys.exit(0)
        except json.JSONDecodeError:
            continue
    sys.exit(1)
PY
  )"; then
    return 1
  fi

  export GCP_CREDENTIALS_JSON="$exported"
}

load_storage_credentials() {
  [[ -f "$STORAGE_CREDS" ]] || return 1
  # shellcheck disable=SC1090
  eval "$("$CONSOLE_ROOT/scripts/export.sh" "$STORAGE_CREDS")"
  export GCP_CREDENTIALS_JSON
}

ensure_credentials() {
  if credentials_json_valid; then
    return 0
  fi
  unset GCP_CREDENTIALS_JSON
  if load_console_dotenv; then
    return 0
  fi
  if load_storage_credentials; then
    return 0
  fi
  if [[ -f "$DEFAULT_CREDS" ]]; then
    # shellcheck disable=SC1090
    eval "$("$CONSOLE_ROOT/scripts/export.sh" "$DEFAULT_CREDS")"
    export GCP_CREDENTIALS_JSON
    return 0
  fi
  echo "error: GCP_CREDENTIALS_JSON is unset" >&2
  echo "hint: manager gcp credentials set --file /path/to/sa.json" >&2
  echo "      (stored at $STORAGE_CREDS)" >&2
  exit 1
}

run_gcp() {
  ensure_credentials
  docker compose -f "$COMPOSE_FILE" run --rm gcp "$@"
}

operator_sa_email() {
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
print(email)
'
}

cloudbuild_submit_denied() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 1
  grep -Eq 'serviceusage\.services\.use|forbidden from accessing the bucket' "$log_file"
}

bucket_from_submit_log() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 1
  sed -n 's/.*forbidden from accessing the bucket \[\([^]]*\)\].*/\1/p' "$log_file" | head -1
}

grant_cloudbuild_submit_access() {
  local log_file="${1:-}"
  local project email bucket member
  ensure_credentials
  project="${GCP_PROJECT:-}"
  if [[ -z "$project" ]]; then
    project="$(run_gcp gcloud config get-value project 2>/dev/null | tail -1 | tr -d '\r')"
  fi
  email="$(operator_sa_email || true)"
  if [[ -z "$project" || -z "$email" ]]; then
    echo "error: cannot grant Cloud Build submit access (missing project or SA email)" >&2
    return 1
  fi
  member="serviceAccount:${email}"
  bucket="$(bucket_from_submit_log "$log_file" || true)"
  bucket="${bucket:-${project}_cloudbuild}"

  local region="${CLOUD_BUILD_REGION:-us-central1}"
  echo "cloudbuild: granting submit access to $email on $project (bucket gs://${bucket})" >&2
  run_gcp gcloud projects add-iam-policy-binding "$project" \
    --member="$member" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None \
    --quiet
  run_gcp gcloud projects add-iam-policy-binding "$project" \
    --member="$member" \
    --role="roles/cloudbuild.builds.editor" \
    --condition=None \
    --quiet
  run_gcp gcloud projects add-iam-policy-binding "$project" \
    --member="$member" \
    --role="roles/storage.objectAdmin" \
    --condition=None \
    --quiet
  echo "cloudbuild: ensuring Cloud Build APIs" >&2
  run_gcp gcloud services enable cloudbuild.googleapis.com storage.googleapis.com \
    --project="$project" || true
  if run_gcp gsutil ls -b "gs://${bucket}" >/dev/null 2>&1; then
    echo "cloudbuild: bucket gs://${bucket} exists" >&2
  else
    echo "cloudbuild: creating missing staging bucket gs://${bucket} in ${region}" >&2
    run_gcp gsutil mb -p "$project" -l "$region" "gs://${bucket}"
  fi
  run_gcp gsutil iam ch "serviceAccount:${email}:objectAdmin" "gs://${bucket}" \
    || run_gcp gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
      --member="$member" \
      --role="roles/storage.objectAdmin" \
      --quiet \
    || echo "cloudbuild: warning: could not set bucket IAM (project objectAdmin may be enough)" >&2
}

require_arg() {
  local name="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "error: missing required argument: $name" >&2
    usage >&2
    exit 1
  fi
}
