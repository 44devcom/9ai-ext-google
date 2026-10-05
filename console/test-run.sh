#!/usr/bin/env bash
# Unit tests for console/run.sh (no live GCP / no image build).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="${ROOT}/console/run.sh"
fail=0

assert_contains() {
  local msg="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "OK ${msg}"
  else
    echo "FAIL ${msg} (missing ${needle})"
    fail=1
  fi
}

[[ -x "$RUN" ]] || { echo "FAIL run.sh not executable"; exit 1; }
bash -n "$RUN" && echo "OK bash -n run.sh" || { echo "FAIL bash -n"; fail=1; }

help_out=$(bash "$RUN" --help)
assert_contains "help Usage" "$help_out" "Usage:"
assert_contains "help Examples" "$help_out" "Examples:"
assert_contains "help no host gcloud" "$help_out" "Host gcloud is not required"

set +e
empty="${tmpdir:-$(mktemp -d)}/nodocker"
mkdir -p "$empty"
out=$(PATH="$empty" /bin/bash "$RUN" gcloud auth list 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 && "$out" == *"docker required"* ]]; then
  echo "OK no docker fails closed"
else
  echo "FAIL no-docker (rc=${rc} out=${out})"
  fail=1
fi

exit "$fail"
