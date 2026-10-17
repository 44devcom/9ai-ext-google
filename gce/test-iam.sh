#!/usr/bin/env bash
# Unit tests for gce/iam.sh key-blocked / impersonation path (no live GCP).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_ok() {
  local msg="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "OK ${msg}"
  else
    echo "FAIL ${msg}"
    fail=1
  fi
}

assert_contains() {
  local msg="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "OK ${msg}"
  else
    echo "FAIL ${msg} (missing ${needle})"
    fail=1
  fi
}

assert_not_contains() {
  local msg="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "FAIL ${msg} (unexpected ${needle})"
    fail=1
  else
    echo "OK ${msg}"
  fi
}

stub_bin="$tmpdir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/gcloud" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  config)
    [[ "${2:-}" == set && "${3:-}" == project ]] && exit 0
    ;;
  auth)
    if [[ "${2:-}" == list ]]; then
      echo "user@example.com"
      exit 0
    fi
    ;;
  services)
    [[ "${2:-}" == enable ]] && exit 0
    ;;
  projects)
    if [[ "${2:-}" == add-iam-policy-binding ]]; then
      exit 0
    fi
    if [[ "${2:-}" == list ]]; then
      echo "stub-project"
      exit 0
    fi
    ;;
  iam)
    if [[ "${2:-}" == service-accounts ]]; then
      case "${3:-}" in
        describe) exit 0 ;;
        create) exit 0 ;;
        keys)
          [[ "${4:-}" == create ]] || exit 1
          echo "ERROR: (gcloud.iam.service-accounts.keys.create) FAILED_PRECONDITION: Key creation is not allowed on this service account." >&2
          echo "  violations:" >&2
          echo "  - type: constraints/iam.disableServiceAccountKeyCreation" >&2
          exit 1
          ;;
        add-iam-policy-binding) exit 0 ;;
      esac
    fi
    ;;
esac
echo "stub gcloud: unhandled: $*" >&2
exit 1
STUB
chmod 755 "$stub_bin/gcloud"

# key_creation_blocked detection (same logic as iam.sh)
key_creation_blocked() {
  local err="$1"
  [[ "$err" == *disableServiceAccountKeyCreation* ]] && return 0
  [[ "$err" == *"Key creation is not allowed"* ]] && return 0
  return 1
}

sample_err='FAILED_PRECONDITION: Key creation is not allowed
type: constraints/iam.disableServiceAccountKeyCreation'
assert_ok "key_creation_blocked detects org policy" key_creation_blocked "$sample_err"
if key_creation_blocked "permission denied"; then
  echo "FAIL key_creation_blocked rejects other errors"
  fail=1
else
  echo "OK key_creation_blocked rejects other errors"
fi

key_out="$tmpdir/nineai-remote-owner.key.json"
export PATH="$stub_bin:$PATH"
export PROJECT=stub-project
export GOOGLE_APPLICATION_CREDENTIALS=
export GOOGLE_CLOUD_PROJECT=
export CLOUDSDK_CORE_PROJECT=
export DEVSHELL_PROJECT_ID=

combined=$(
  cd "$ROOT" && ./iam.sh ensure-owner-sa --project stub-project --key-out "$key_out" 2>&1
) || true

assert_ok "ensure-owner-sa exits 0 when keys blocked" bash -c "
  export PATH='$stub_bin':\$PATH PROJECT=stub-project GOOGLE_APPLICATION_CREDENTIALS=
  cd '$ROOT' && ./iam.sh ensure-owner-sa --project stub-project --key-out '$key_out' >/dev/null
"

combined=$(
  export PATH="$stub_bin:$PATH" PROJECT=stub-project GOOGLE_APPLICATION_CREDENTIALS=
  cd "$ROOT" && ./iam.sh ensure-owner-sa --project stub-project --key-out "$key_out" 2>&1
)

assert_contains "stderr mentions TokenCreator" "$combined" "serviceAccountTokenCreator"
assert_contains "stderr mentions impersonate" "$combined" "impersonate_service_account"
assert_contains "stderr remote_manage=impersonation" "$combined" "remote_manage=impersonation"
assert_not_contains "stdout has no key JSON" "$(
  export PATH="$stub_bin:$PATH" PROJECT=stub-project GOOGLE_APPLICATION_CREDENTIALS=
  cd "$ROOT" && ./iam.sh ensure-owner-sa --project stub-project --key-out "$key_out" 2>/dev/null || true
)" '"type": "service_account"'
[[ ! -f "$key_out" ]] && echo "OK key file not created when blocked" || { echo "FAIL key file created when blocked"; fail=1; }

if [[ "$fail" -eq 0 ]]; then
  echo "All iam tests passed."
else
  echo "Some iam tests failed."
  exit 1
fi
