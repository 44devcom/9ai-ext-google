#!/usr/bin/env bash
# One-shot Cloud Shell bootstrap: Owner SA + show.
# Prefer the Open in Cloud Shell tutorial; run this from the clickable step.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
chmod 755 lib.sh iam.sh cloudshell-bootstrap.sh
./iam.sh ensure-owner-sa "$@"
./iam.sh show
