#!/usr/bin/env bash
# Non-interactive Cloud Shell bootstrap: pick an active GCP project, Owner SA,
# write ./nineai-remote-owner.key.json and print JSON on stdout when allowed;
# when org policy blocks keys, print impersonation instructions instead.
# Cloud Shell Editor runs this on folderOpen via gce/.vscode/tasks.json.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
chmod 755 lib.sh iam.sh cloudshell-bootstrap.sh

LOCK="${XDG_RUNTIME_DIR:-/tmp}/nineai-cloudshell-bootstrap.lock"
exec 9>"$LOCK"
flock 9

./iam.sh ensure-owner-sa "$@"
