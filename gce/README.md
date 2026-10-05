# GCE ensure helpers + IAM

Bash libraries for Cloud Shell / operator deploy scripts.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/44devcom/9ai-ext-google&cloudshell_workspace=gce)

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
optionally writes a key JSON for remote `gcloud` / automation (Cloud Shell,
CI, laptop).

```bash
# In Cloud Shell (or any host with gcloud + your user Owner login):
gcloud auth login
gcloud config set project YOUR_PROJECT
chmod 755 *.sh iam.sh
./iam.sh ensure-owner-sa
# writes ./9ai-remote-owner.key.json (gitignored) and binds roles/owner

./iam.sh show
./iam.sh grant-owner          # re-apply owner if IAM drifted
./iam.sh enable-apis          # IAM / Compute / Resource Manager only
```

Options: `--sa-id`, `--display-name`, `--key-out PATH`, `--no-key`, `--project`.

Activate the key elsewhere:

```bash
gcloud auth activate-service-account --key-file=./9ai-remote-owner.key.json
# or: export GOOGLE_APPLICATION_CREDENTIALS=$PWD/9ai-remote-owner.key.json
```

Do **not** commit the key. Prefer vault / a secrets store after download.
`roles/owner` is powerful; revoke unused keys with
`gcloud iam service-accounts keys list` / `delete`.
