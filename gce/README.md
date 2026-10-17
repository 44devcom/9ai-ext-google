# GCE ensure helpers + IAM

Bash libraries for Cloud Shell / operator deploy scripts.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/44devcom/9ai-ext-google&cloudshell_git_branch=master&cloudshell_workspace=gce&cloudshell_tutorial=tutorial.md&cloudshell_print=cloudshell-print.txt)

That link opens workspace `gce`, prints [`cloudshell-print.txt`](cloudshell-print.txt),
and launches [`tutorial.md`](tutorial.md). Opening `gce` runs
[`cloudshell-bootstrap.sh`](cloudshell-bootstrap.sh) automatically (Editor
`folderOpen` task): it selects an active GCP project, ensures the Owner SA,
writes `./nineai-remote-owner.key.json` when allowed, and prints key JSON or
impersonation instructions when org policy blocks keys.

If bootstrap did not run: `chmod 755 *.sh && ./cloudshell-bootstrap.sh`.
If the tutorial panel is missing: `cloudshell launch-tutorial tutorial.md`.
If auto-clone fails (`terminal prompts disabled`): `gh auth login` then
[`cloudshell-start.sh`](cloudshell-start.sh) (runs bootstrap).

## SSH VPS (no application install)

[`ssh-vps.sh`](ssh-vps.sh) creates or reuses a Debian VM, static IP, and TCP 22.
It does **not** clone software or set a startup-script. Install a router
afterwards over SSH (for example
`vpnbox setup --role router --method ssh --router debian@IP`).

```bash
chmod 755 *.sh
./ssh-vps.sh vpnbox1
./ssh-vps.sh vpnbox1 --extra-ports tcp:9418,udp:1194
./ssh-vps.sh vpnbox1 --dry-run
./ssh-vps.sh vpnbox1 --delete
```

Prints `ssh=debian@<static-ip>` and `static_ip=`. Host **gcloud is not
required**: without it, the script re-enters through
[`../console/run.sh`](../console/run.sh) (Docker console image). Tests:
`bash gce/test-ssh-vps.sh` and `bash console/test-run.sh`.

## Idempotent GCE resources

Source from an operator deploy script (for example 9ai-network Cloud Shell
`gcp/deploy.sh`):

```bash
# shellcheck source=/dev/null
. "${EXT_GOOGLE_ROOT}/gce/lib.sh"

gce_ensure_network "${NAME}-network"
PUBLIC_IP=$(gce_ensure_address "${NAME}-ip" "$REGION")
gce_ensure_firewall "${NAME}-fw-ssh" "${NAME}-network" "vpnbox-${NAME}" "tcp:22"
gce_ensure_instance "${NAME}-vm" "$ZONE" \
  --machine-type=e2-small \
  --network="${NAME}-network" \
  --tags="vpnbox-${NAME}" \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-balanced \
  --address="$PUBLIC_IP" \
  --metadata-from-file="startup-script=${STARTUP_TMP}"
```

On create, `gce_ensure_instance` always passes `--no-shielded-vtpm` and
`--no-shielded-integrity-monitoring` (vTPM and Integrity Monitoring off).
Secure Boot is left at the image/API default.

When the instance already exists, `gce_ensure_instance` refreshes
`--metadata*` args via `add-metadata` and runs `instances reset` (same disk
and reserved IP).

Teardown: `gce_delete_instance`, `gce_delete_firewall`, `gce_delete_address`,
`gce_delete_network`.

Requires `gcloud` on `PATH` and an authenticated project.

## Owner service account (remote manage)

[`iam.sh`](iam.sh) creates or reuses a project **Owner** service account and
optionally writes a key JSON for remote `gcloud` / automation.

**Cloud Shell (primary):** use the Open button and tutorial above, or:

```bash
chmod 755 *.sh && ./cloudshell-bootstrap.sh
```

**Any host (fallback)** with `gcloud` and your user Owner login:

```bash
./iam.sh ensure-owner-sa
./iam.sh show
./iam.sh grant-owner          # re-apply owner if IAM drifted
./iam.sh enable-apis          # IAM / Compute / Resource Manager only
```

Options: `--sa-id`, `--display-name`, `--key-out PATH`, `--no-key`, `--project`.
Project also comes from `GOOGLE_CLOUD_PROJECT` / `CLOUDSDK_CORE_PROJECT` /
`DEVSHELL_PROJECT_ID`, `gcloud` config, or the first ACTIVE project.

Activate the key elsewhere (when key creation succeeds):

```bash
gcloud auth activate-service-account --key-file=./nineai-remote-owner.key.json
# or: export GOOGLE_APPLICATION_CREDENTIALS=$PWD/nineai-remote-owner.key.json
```

### If key creation is blocked

When `ensure-owner-sa` reports `constraints/iam.disableServiceAccountKeyCreation`,
use host `gcloud` impersonation (bootstrap grants your active principal
`roles/iam.serviceAccountTokenCreator` on the Owner SA):

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud config set auth/impersonate_service_account nineai-remote-owner@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

`console/run.sh` still requires a key JSON file; impersonation is not wired there.

Tests: `bash gce/test-iam.sh` (no live GCP).

Do **not** commit the key. Prefer vault / a secrets store after download.
`roles/owner` is powerful; revoke unused keys with
`gcloud iam service-accounts keys list` / `delete`.
