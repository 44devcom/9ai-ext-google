#!/usr/bin/env bash
# Shared helpers for Artifact Registry scripts. Sourced, not executed.

set -euo pipefail

CONSOLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$CONSOLE_ROOT/../../../../.." && pwd)"
COMPOSE_FILE="$CONSOLE_ROOT/docker-compose.yml"
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

ensure_credentials() {
  if credentials_json_valid; then
    return 0
  fi
  unset GCP_CREDENTIALS_JSON
  if load_console_dotenv; then
    return 0
  fi
  if [[ -f "$DEFAULT_CREDS" ]]; then
    # shellcheck disable=SC1090
    eval "$("$CONSOLE_ROOT/scripts/export.sh" "$DEFAULT_CREDS")"
    export GCP_CREDENTIALS_JSON
    return 0
  fi
  echo "error: GCP_CREDENTIALS_JSON is unset and $DEFAULT_CREDS was not found" >&2
  echo "hint: eval \"\$($CONSOLE_ROOT/scripts/export.sh /path/to/sa.json)\"" >&2
  exit 1
}

run_gcp() {
  ensure_credentials
  docker compose -f "$COMPOSE_FILE" run --rm gcp "$@"
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
