#!/usr/bin/env bash
# Idempotent GCE helpers for Cloud Shell / operator deploy scripts.
# Source this file; do not execute. Requires gcloud on PATH.
#
# Provides:
#   gce_ensure_network NAME
#   gce_ensure_address NAME REGION   → prints reserved IP
#   gce_ensure_firewall RULE NETWORK TAG ALLOW
#   gce_ensure_instance VM ZONE ...  (create, or add-metadata + reset)
#   gce_delete_instance VM ZONE
#   gce_delete_firewall RULE
#   gce_delete_address NAME REGION
#   gce_delete_network NAME

set -euo pipefail

gce_ensure_network() {
  local name="$1"
  if gcloud compute networks describe "$name" --quiet >/dev/null 2>&1; then
    echo "network ${name} exists"
    return 0
  fi
  gcloud compute networks create "$name" --subnet-mode=auto --quiet
}

gce_ensure_address() {
  local name="$1" region="$2" ip
  if ! gcloud compute addresses describe "$name" --region="$region" --quiet >/dev/null 2>&1; then
    gcloud compute addresses create "$name" --region="$region" --quiet
  else
    echo "address ${name} exists" >&2
  fi
  ip=$(gcloud compute addresses describe "$name" --region="$region" --format='get(address)')
  [[ -n "$ip" ]] || { echo "failed to resolve static IP for ${name}" >&2; return 1; }
  printf '%s\n' "$ip"
}

gce_ensure_firewall() {
  local rule="$1" network="$2" tag="$3" allow="$4"
  if gcloud compute firewall-rules describe "$rule" --quiet >/dev/null 2>&1; then
    echo "firewall ${rule} exists"
    return 0
  fi
  gcloud compute firewall-rules create "$rule" \
    --network="$network" \
    --allow="$allow" \
    --target-tags="$tag" \
    --direction=INGRESS \
    --priority=1000 \
    --quiet
}

# Remaining args are forwarded to instances create / add-metadata.
# Required create flags (when VM is new): --machine-type --network --tags
# --image-family --image-project --boot-disk-size --boot-disk-type --address
# Plus optional --metadata-from-file= / --metadata= / --scopes=
gce_ensure_instance() {
  local vm="$1" zone="$2"
  shift 2
  local -a extra=("$@")
  local -a meta=()
  local -a create_extra=()
  local arg
  for arg in "${extra[@]}"; do
    case "$arg" in
      --metadata-from-file=*|--metadata=*)
        meta+=("$arg")
        ;;
      *)
        create_extra+=("$arg")
        ;;
    esac
  done

  if gcloud compute instances describe "$vm" --zone="$zone" --quiet >/dev/null 2>&1; then
    echo "instance ${vm} exists; refreshing metadata and resetting"
    if ((${#meta[@]})); then
      gcloud compute instances add-metadata "$vm" --zone="$zone" "${meta[@]}" --quiet
    fi
    gcloud compute instances reset "$vm" --zone="$zone" --quiet
    return 0
  fi

  gcloud compute instances create "$vm" \
    --zone="$zone" \
    "${create_extra[@]}" \
    "${meta[@]}" \
    --quiet
}

gce_delete_instance() {
  local vm="$1" zone="$2"
  if gcloud compute instances describe "$vm" --zone="$zone" --quiet >/dev/null 2>&1; then
    gcloud compute instances delete "$vm" --zone="$zone" --quiet
  else
    echo "instance ${vm} absent"
  fi
}

gce_delete_firewall() {
  local rule="$1"
  if gcloud compute firewall-rules describe "$rule" --quiet >/dev/null 2>&1; then
    gcloud compute firewall-rules delete "$rule" --quiet
  else
    echo "firewall ${rule} absent"
  fi
}

gce_delete_address() {
  local name="$1" region="$2"
  if gcloud compute addresses describe "$name" --region="$region" --quiet >/dev/null 2>&1; then
    gcloud compute addresses delete "$name" --region="$region" --quiet
  else
    echo "address ${name} absent"
  fi
}

gce_delete_network() {
  local name="$1"
  if gcloud compute networks describe "$name" --quiet >/dev/null 2>&1; then
    gcloud compute networks delete "$name" --quiet || echo "network ${name} not deleted (still in use?)"
  else
    echo "network ${name} absent"
  fi
}
