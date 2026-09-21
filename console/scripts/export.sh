#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  export.sh                 Read JSON from stdin (paste, then Enter)
  export.sh KEY.json        Read JSON from a service account key file
  export.sh --help            Show this help

Prints a shell export line for GCP_CREDENTIALS_JSON to stdout.
Does not write any files. Load it with:

  eval "$(./scripts/export.sh path/to/key.json)"
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  echo "error: too many arguments" >&2
  usage >&2
  exit 1
fi

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

if [[ $# -eq 1 ]]; then
  if [[ ! -f "$1" ]]; then
    echo "error: file not found: $1" >&2
    exit 1
  fi
  if [[ ! -r "$1" ]]; then
    echo "error: file is not readable: $1" >&2
    exit 1
  fi
  INPUT="$(cat "$1")"
else
  INPUT="$(read_pasted_json)"
fi

if [[ -z "$INPUT" ]]; then
  echo "error: no JSON input provided" >&2
  exit 1
fi

python3 -c '
import json
import sys

raw = sys.argv[1]

try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"error: invalid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

required = ("type", "client_email", "private_key")
missing = [field for field in required if not data.get(field)]
if missing:
    print(
        "error: JSON is missing required fields: " + ", ".join(missing),
        file=sys.stderr,
    )
    sys.exit(1)

if data.get("type") != "service_account":
    print(
        "error: JSON must be a service account key (type=service_account)",
        file=sys.stderr,
    )
    sys.exit(1)

minified = json.dumps(data, separators=(",", ":"))

sq = chr(39)
dq = chr(34)
bs = chr(92)

if sq not in minified:
    print(f"export GCP_CREDENTIALS_JSON={sq}{minified}{sq}")
else:
    escaped = minified.replace(bs, bs + bs).replace(dq, bs + dq)
    print(f"export GCP_CREDENTIALS_JSON={dq}{escaped}{dq}")

project_id = data.get("project_id", "")
if project_id:
    print(f"# project_id: {project_id}", file=sys.stderr)
else:
    print("# warning: project_id not found in JSON", file=sys.stderr)
' "$INPUT"
