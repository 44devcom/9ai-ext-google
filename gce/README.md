# GCE ensure helpers

Bash library for idempotent GCE resource create-or-reuse. Source from an
operator deploy script (for example 9ai-network Cloud Shell `gcp/deploy.sh`):

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

When the instance already exists, `gce_ensure_instance` refreshes
`--metadata*` args via `add-metadata` and runs `instances reset` (same disk
and reserved IP).

Teardown: `gce_delete_instance`, `gce_delete_firewall`, `gce_delete_address`,
`gce_delete_network`.

Requires `gcloud` on `PATH` and an authenticated project.
