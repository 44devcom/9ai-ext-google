#!/usr/bin/env bash
set -euo pipefail

CREDS_FILE="/secrets/gcp-key.json"

read_pasted_json() {
  local line input=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$input" && -z "$line" ]] && continue
    input="${input:+$input$'\n'}$line"
    if python3 -c 'import json, sys; json.loads(sys.argv[1])' "$input" 2>/dev/null; then
      printf '%s' "$input"
      return 0
    fi
  done
  printf '%s' "$input"
}

if [[ -z "${GCP_CREDENTIALS_JSON:-}" ]]; then
  if [[ -t 0 ]]; then
    echo "GCP_CREDENTIALS_JSON is not set." >&2
    echo "Paste service account JSON, then press Enter:" >&2
    GCP_CREDENTIALS_JSON="$(read_pasted_json)"
    export GCP_CREDENTIALS_JSON
    if [[ -z "$GCP_CREDENTIALS_JSON" ]]; then
      echo "error: no JSON input provided" >&2
      exit 1
    fi
  else
    echo "error: GCP_CREDENTIALS_JSON is not set" >&2
    echo "Set GCP_CREDENTIALS_JSON to your minified service account JSON," >&2
    echo "or run interactively to paste credentials." >&2
    exit 1
  fi
fi

mkdir -p /secrets

if ! PROJECT_ID="$(python3 -c "
import json
import os
import sys

raw = os.environ['GCP_CREDENTIALS_JSON']
for candidate in (raw, raw.encode().decode('unicode_escape')):
    try:
        data = json.loads(candidate)
        break
    except json.JSONDecodeError:
        data = None
else:
    print(f'error: invalid JSON in GCP_CREDENTIALS_JSON: not valid JSON', file=sys.stderr)
    sys.exit(1)

required = ('type', 'client_email', 'private_key')
missing = [field for field in required if not data.get(field)]
if missing:
    print(
        'error: GCP_CREDENTIALS_JSON is missing required fields: '
        + ', '.join(missing),
        file=sys.stderr,
    )
    sys.exit(1)

if data.get('type') != 'service_account':
    print(
        'error: GCP_CREDENTIALS_JSON must be a service account key (type=service_account)',
        file=sys.stderr,
    )
    sys.exit(1)

with open('${CREDS_FILE}', 'w', encoding='utf-8') as handle:
    json.dump(data, handle)

print(data.get('project_id', ''), end='')
")"; then
  exit 1
fi

chmod 600 "$CREDS_FILE"

export GOOGLE_APPLICATION_CREDENTIALS="$CREDS_FILE"

gcloud auth activate-service-account --key-file="$CREDS_FILE" --quiet

RESOLVED_PROJECT="${GCP_PROJECT:-$PROJECT_ID}"
if [[ -n "$RESOLVED_PROJECT" ]]; then
  gcloud config set project "$RESOLVED_PROJECT" --quiet
elif [[ -z "${GCP_PROJECT:-}" ]]; then
  echo "warning: no project_id in credentials and GCP_PROJECT is unset" >&2
  echo "warning: some gcloud commands may require --project" >&2
fi

exec "$@"
