#!/usr/bin/env bash
# Non-interactive Cloud Shell bootstrap: pick an active GCP project, Owner SA,
# write ./nineai-remote-owner.key.json and print the JSON on stdout.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
chmod 755 lib.sh iam.sh cloudshell-bootstrap.sh
./iam.sh ensure-owner-sa "$@"
