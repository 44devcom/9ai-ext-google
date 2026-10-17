#!/usr/bin/env bash
# Manage a project Owner service account for remote gcloud / Cloud Shell use.
# Usage:
#   ./iam.sh ensure-owner-sa [--sa-id ID] [--display-name NAME] [--key-out PATH] [--no-key] [--project ID]
#   ./iam.sh show [--sa-id ID] [--project ID]
#   ./iam.sh grant-owner [--sa-id ID] [--project ID]
#   ./iam.sh enable-apis [--project ID]
set -euo pipefail

DEFAULT_SA_ID="nineai-remote-owner"
DEFAULT_DISPLAY="9ai remote owner"
DEFAULT_KEY_OUT="./${DEFAULT_SA_ID}.key.json"

APIS=(
  cloudresourcemanager.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  compute.googleapis.com
  serviceusage.googleapis.com
)

usage() {
  cat <<'EOF'
Usage:
  ./iam.sh ensure-owner-sa [options]   Create/reuse SA, grant roles/owner, key JSON or impersonation hints
  ./iam.sh show [options]              Print SA email and project IAM bindings for it
  ./iam.sh grant-owner [options]       Ensure roles/owner on an existing SA
  ./iam.sh enable-apis [options]       Enable IAM / Compute / Resource Manager APIs
  ./iam.sh --help

Options:
  --sa-id ID            Service account id (local part before @). Default: nineai-remote-owner
  --display-name NAME   Display name for create. Default: 9ai remote owner
  --key-out PATH        Where to write a new key JSON (ensure-owner-sa). Default: ./nineai-remote-owner.key.json
  --no-key              Do not create or write a key file
  --project ID          GCP project (env, gcloud config, else first ACTIVE)

Requires a logged-in principal that can create service accounts and set project
IAM (typically your user Owner). When org policy allows keys, the JSON is for
remote automation — do not commit it. When keys are blocked
(constraints/iam.disableServiceAccountKeyCreation), ensure-owner-sa grants
TokenCreator to your active principal and prints impersonation commands.
EOF
}

WRITE_KEY_STATUS=""

key_creation_blocked() {
  local err="$1"
  [[ "$err" == *disableServiceAccountKeyCreation* ]] && return 0
  [[ "$err" == *"Key creation is not allowed"* ]] && return 0
  return 1
}

active_gcloud_account() {
  gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1
}

iam_member_for_account() {
  local acct="$1"
  if [[ "$acct" == *@*.iam.gserviceaccount.com ]]; then
    printf 'serviceAccount:%s\n' "$acct"
  else
    printf 'user:%s\n' "$acct"
  fi
}

grant_impersonation_for_active_principal() {
  local email="$1" acct member
  acct=$(active_gcloud_account)
  if [[ -z "$acct" ]]; then
    echo "warning: no active gcloud account; cannot grant roles/iam.serviceAccountTokenCreator" >&2
    return 1
  fi
  member=$(iam_member_for_account "$acct")
  echo "granting roles/iam.serviceAccountTokenCreator to ${member} on ${email}" >&2
  gcloud iam service-accounts add-iam-policy-binding "$email" \
    --member="$member" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --quiet >/dev/null
  printf '%s\n' "$acct"
}

print_impersonation_instructions() {
  local project="$1" email="$2" principal="${3:-}"
  cat >&2 <<EOF

Org policy blocks service account keys. Use impersonation for remote gcloud instead.

  gcloud auth login
  gcloud config set project ${project}
  gcloud config set auth/impersonate_service_account ${email}

Or per command:
  gcloud compute instances list --impersonate-service-account=${email}

The Docker console (console/run.sh) still requires a key file or GCP_CREDENTIALS_JSON.
EOF
  if [[ -n "$principal" ]]; then
    echo "impersonator=${principal}" >&2
  fi
}

die() { echo "error: $*" >&2; exit 1; }

gac_project_id() {
  local f="${GOOGLE_APPLICATION_CREDENTIALS:-}"
  [[ -n "$f" && -f "$f" ]] || return 0
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("project_id",""))' "$f" 2>/dev/null || true
}

require_gcloud() {
  command -v gcloud >/dev/null || die "gcloud required"
  local gac="${GOOGLE_APPLICATION_CREDENTIALS:-}"
  if [[ -n "$gac" && -f "$gac" ]]; then
    gcloud auth activate-service-account --key-file="$gac" --quiet
  fi
}

resolve_project() {
  local p="${PROJECT:-}"
  if [[ -z "$p" || "$p" == "(unset)" ]]; then
    p="${GOOGLE_CLOUD_PROJECT:-${CLOUDSDK_CORE_PROJECT:-${DEVSHELL_PROJECT_ID:-}}}"
  fi
  if [[ -z "$p" || "$p" == "(unset)" ]]; then
    p=$(gac_project_id)
  fi
  if [[ -z "$p" || "$p" == "(unset)" ]]; then
    p=$(gcloud config get-value project 2>/dev/null || true)
  fi
  if [[ -z "$p" || "$p" == "(unset)" ]]; then
    p=$(gcloud projects list \
      --filter='lifecycleState:ACTIVE' \
      --format='value(projectId)' \
      --sort-by=projectId \
      --limit=1 \
      --quiet 2>/dev/null || true)
  fi
  [[ -n "$p" && "$p" != "(unset)" ]] \
    || die "no active GCP project (not logged in, or no projects)"
  gcloud config set project "$p" --quiet
  printf '%s\n' "$p"
}

sa_email() {
  local project="$1" sa_id="$2"
  printf '%s@%s.iam.gserviceaccount.com\n' "$sa_id" "$project"
}

cmd_enable_apis() {
  local project
  project=$(resolve_project)
  echo "project=${project}" >&2
  echo "enabling APIs: ${APIS[*]}" >&2
  gcloud services enable "${APIS[@]}" --project="$project" --quiet
  echo "apis enabled" >&2
}

ensure_sa() {
  local project="$1" sa_id="$2" display="$3" email
  email=$(sa_email "$project" "$sa_id")
  if gcloud iam service-accounts describe "$email" --project="$project" --quiet >/dev/null 2>&1; then
    echo "service_account ${email} exists" >&2
  else
    echo "creating service_account ${email}" >&2
    gcloud iam service-accounts create "$sa_id" \
      --project="$project" \
      --display-name="$display" \
      --quiet \
      || die "failed to create service account ${email} (id must match [a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9])"
  fi
  printf '%s\n' "$email"
}

grant_owner() {
  local project="$1" email="$2"
  echo "ensuring roles/owner for ${email} on ${project}" >&2
  gcloud projects add-iam-policy-binding "$project" \
    --member="serviceAccount:${email}" \
    --role="roles/owner" \
    --condition=None \
    --quiet >/dev/null
  echo "owner binding ok" >&2
}

write_key() {
  local project="$1" email="$2" out="$3" err
  WRITE_KEY_STATUS=""
  if [[ -f "$out" ]]; then
    echo "key file already exists: ${out} (not overwritten)" >&2
    WRITE_KEY_STATUS=existing
    cat "$out"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  echo "creating key -> ${out}" >&2
  if err=$(gcloud iam service-accounts keys create "$out" \
    --iam-account="$email" \
    --project="$project" \
    --quiet 2>&1); then
    chmod 600 "$out"
    echo "key_written=${out}" >&2
    WRITE_KEY_STATUS=created
    cat "$out"
    return 0
  fi
  if key_creation_blocked "$err"; then
    echo "key creation blocked by org policy (constraints/iam.disableServiceAccountKeyCreation)" >&2
    WRITE_KEY_STATUS=blocked
    return 0
  fi
  echo "$err" >&2
  die "failed to create service account key"
}

cmd_ensure_owner_sa() {
  local project sa_id display key_out no_key email
  project=$(resolve_project)
  sa_id="${SA_ID:-$DEFAULT_SA_ID}"
  display="${DISPLAY_NAME:-$DEFAULT_DISPLAY}"
  key_out="${KEY_OUT:-$DEFAULT_KEY_OUT}"
  no_key="${NO_KEY:-0}"

  cmd_enable_apis
  email=$(ensure_sa "$project" "$sa_id" "$display")
  grant_owner "$project" "$email"
  if [[ "$no_key" != 1 ]]; then
    write_key "$project" "$email" "$key_out"
    case "${WRITE_KEY_STATUS}" in
      blocked)
        principal=""
        principal=$(grant_impersonation_for_active_principal "$email" || true)
        print_impersonation_instructions "$project" "$email" "$principal"
        echo "remote_manage=impersonation" >&2
        ;;
      created|existing)
        echo "remote_manage=key_file" >&2
        echo "use with: export GOOGLE_APPLICATION_CREDENTIALS=${key_out}" >&2
        ;;
      "")
        die "write_key left WRITE_KEY_STATUS unset"
        ;;
    esac
  else
    echo "skipping key (--no-key)" >&2
  fi
  echo "service_account=${email}" >&2
  echo "project=${project}" >&2
}

cmd_grant_owner() {
  local project sa_id email
  project=$(resolve_project)
  sa_id="${SA_ID:-$DEFAULT_SA_ID}"
  email=$(sa_email "$project" "$sa_id")
  gcloud iam service-accounts describe "$email" --project="$project" --quiet >/dev/null 2>&1 \
    || die "service account missing: ${email} (run ensure-owner-sa)"
  grant_owner "$project" "$email"
}

cmd_show() {
  local project sa_id email
  project=$(resolve_project)
  sa_id="${SA_ID:-$DEFAULT_SA_ID}"
  email=$(sa_email "$project" "$sa_id")
  echo "project=${project}"
  echo "service_account=${email}"
  if gcloud iam service-accounts describe "$email" --project="$project" --quiet >/dev/null 2>&1; then
    gcloud iam service-accounts describe "$email" --project="$project" \
      --format='yaml(email,displayName,disabled,oauth2ClientId)'
  else
    echo "status=absent"
  fi
  echo "--- project IAM bindings for this SA ---"
  gcloud projects get-iam-policy "$project" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${email}" \
    --format='table(bindings.role)' 2>/dev/null || true
}

# --- arg parse ---
CMD=""
SA_ID=""
DISPLAY_NAME=""
KEY_OUT=""
NO_KEY=0
PROJECT=""

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ -n "${1:-}" ]] || { usage >&2; exit 1; }

case "$1" in
  ensure-owner-sa|show|grant-owner|enable-apis)
    CMD="$1"
    shift
    ;;
  *)
    die "unknown command: $1 (try --help)"
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --sa-id) SA_ID="${2:-}"; [[ -n "$SA_ID" ]] || die "--sa-id requires a value"; shift 2 ;;
    --sa-id=*) SA_ID="${1#*=}"; shift ;;
    --display-name) DISPLAY_NAME="${2:-}"; [[ -n "$DISPLAY_NAME" ]] || die "--display-name requires a value"; shift 2 ;;
    --display-name=*) DISPLAY_NAME="${1#*=}"; shift ;;
    --key-out) KEY_OUT="${2:-}"; [[ -n "$KEY_OUT" ]] || die "--key-out requires a value"; shift 2 ;;
    --key-out=*) KEY_OUT="${1#*=}"; shift ;;
    --no-key) NO_KEY=1; shift ;;
    --project) PROJECT="${2:-}"; [[ -n "$PROJECT" ]] || die "--project requires a value"; shift 2 ;;
    --project=*) PROJECT="${1#*=}"; shift ;;
    -*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

require_gcloud

case "$CMD" in
  ensure-owner-sa) cmd_ensure_owner_sa ;;
  show) cmd_show ;;
  grant-owner) cmd_grant_owner ;;
  enable-apis) cmd_enable_apis ;;
esac
