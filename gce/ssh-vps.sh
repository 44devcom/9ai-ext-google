#!/usr/bin/env bash
# Create or reuse a Debian GCE VM with a static IP and SSH (TCP 22).
# Does not install vpnbox. No startup-script.
# Usage:
#   ./ssh-vps.sh <name> [--extra-ports tcp:9418,udp:1194] [--dry-run]
#   ./ssh-vps.sh <name> --delete
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${ROOT}/lib.sh"

_wants_local() {
  [[ $# -eq 0 ]] && return 0
  local a
  for a in "$@"; do
    case "$a" in
      -h|--help|--dry-run) return 0 ;;
    esac
  done
  return 1
}

if ! command -v gcloud >/dev/null 2>&1 && [[ "${EXT_GOOGLE_IN_CONSOLE:-}" != 1 ]] && ! _wants_local "$@"; then
  next_pub=0
  rewritten=()
  for a in "$@"; do
    if [[ "$next_pub" -eq 1 ]]; then
      SSH_VPS_PUBKEY="$(cat "$a")"
      export SSH_VPS_PUBKEY
      next_pub=0
      continue
    fi
    if [[ "$a" == --ssh-pubkey ]]; then
      next_pub=1
      continue
    fi
    rewritten+=("$a")
  done
  exec "${ROOT}/../console/run.sh" /ext-google/gce/ssh-vps.sh "${rewritten[@]+"${rewritten[@]}"}"
fi

NAME=""
ZONE="${CLOUDSDK_COMPUTE_ZONE:-europe-west1-b}"
REGION="${CLOUDSDK_COMPUTE_REGION:-europe-west1}"
VMTYPE="e2-small"
DISK_GB=20
SSH_USER="debian"
SSH_PUBKEY_FILE=""
EXTRA_PORTS=""
DRY_RUN=0
DO_DELETE=0
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"

usage() {
  cat <<'EOF'
Usage:
  ./ssh-vps.sh <name> [options]
  ./ssh-vps.sh <name> --delete
  ./ssh-vps.sh --help

Create or reuse <name>-vm, static IP <name>-ip, VPC <name>-network,
firewall <name>-fw-ssh (tcp:22). No startup-script and no vpnbox install.

Options:
  --zone ZONE              Default: europe-west1-b (or CLOUDSDK_COMPUTE_ZONE)
  --region REGION          Default: europe-west1
  --machine-type TYPE      Default: e2-small
  --disk-gb N              Default: 20
  --ssh-user USER          Printed in ssh= (default: debian)
  --ssh-pubkey FILE        Inject metadata ssh-keys=<user>:<file>
  --extra-ports LIST       Comma-separated allow specs, e.g. tcp:9418,udp:1194
  --dry-run                Print steps; do not call gcloud
  --delete                 Tear down instance, firewalls, address, network
  -h, --help

Examples:
  ./ssh-vps.sh vpnbox1
  ./ssh-vps.sh vpnbox1 --extra-ports tcp:9418,udp:1194
  ./ssh-vps.sh vpnbox1 --dry-run
  ./ssh-vps.sh vpnbox1 --delete
EOF
}

die() {
  echo "Error: $*" >&2
  echo "  ./ssh-vps.sh vpnbox1" >&2
  exit 1
}

require_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
    die "name must match ^[a-z][a-z0-9-]{0,30}$"
  fi
}

port_slug() {
  local spec="$1"
  echo "$spec" | tr ':/' '-'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --zone) ZONE="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --machine-type) VMTYPE="$2"; shift 2 ;;
    --disk-gb) DISK_GB="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-pubkey) SSH_PUBKEY_FILE="$2"; shift 2 ;;
    --extra-ports) EXTRA_PORTS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --delete) DO_DELETE=1; shift ;;
    --*) die "unknown option $1" ;;
    *)
      if [[ -n "$NAME" ]]; then
        die "unexpected extra argument $1"
      fi
      NAME="$1"
      shift
      ;;
  esac
done

[[ -n "$NAME" ]] || die "name is required"
require_name "$NAME"

VM="${NAME}-vm"
ADDR="${NAME}-ip"
NET="${NAME}-network"
TAG="ssh-vps-${NAME}"
FW_SSH="${NAME}-fw-ssh"

IFS=',' read -ra EXTRA_ARR <<< "${EXTRA_PORTS}"
extras=()
for p in "${EXTRA_ARR[@]}"; do
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  [[ -n "$p" ]] && extras+=("$p")
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "step: ensure network ${NET}"
  echo "step: ensure address ${ADDR} region=${REGION}"
  echo "step: firewall ${FW_SSH} tcp:22"
  for p in "${extras[@]+"${extras[@]}"}"; do
    echo "step: firewall ${NAME}-fw-$(port_slug "$p") ${p}"
  done
  echo "step: instance ${VM} ${IMAGE_FAMILY} no startup-script"
  if [[ -n "$SSH_PUBKEY_FILE" || -n "${SSH_VPS_PUBKEY:-}" ]]; then
    echo "step: metadata ssh-keys ${SSH_USER}"
  fi
  echo "ssh=${SSH_USER}@STATIC_IP"
  echo "static_ip=STATIC_IP"
  exit 0
fi

command -v gcloud >/dev/null || die "gcloud missing; 9ai-ext-google console/run.sh should have wrapped this"

if [[ "$DO_DELETE" -eq 1 ]]; then
  gce_delete_instance "$VM" "$ZONE"
  gce_delete_firewall "$FW_SSH"
  for p in "${extras[@]+"${extras[@]}"}"; do
    gce_delete_firewall "${NAME}-fw-$(port_slug "$p")"
  done
  # Common router extras even if --extra-ports omitted on delete
  gce_delete_firewall "${NAME}-fw-tcp-9418"
  gce_delete_firewall "${NAME}-fw-udp-1194"
  gce_delete_address "$ADDR" "$REGION"
  gce_delete_network "$NET"
  echo "deleted ${NAME}"
  exit 0
fi

echo "project=$(gcloud config get-value project 2>/dev/null)"
echo "zone=${ZONE} region=${REGION} vm=${VM} type=${VMTYPE}"

gce_ensure_network "$NET"
PUBLIC_IP=$(gce_ensure_address "$ADDR" "$REGION")
echo "static_ip=${PUBLIC_IP}"

gce_ensure_firewall "$FW_SSH" "$NET" "$TAG" "tcp:22"
for p in "${extras[@]+"${extras[@]}"}"; do
  gce_ensure_firewall "${NAME}-fw-$(port_slug "$p")" "$NET" "$TAG" "$p"
done

META_ARGS=()
if [[ -n "$SSH_PUBKEY_FILE" ]]; then
  SSH_VPS_PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
fi
if [[ -n "${SSH_VPS_PUBKEY:-}" ]]; then
  META_ARGS+=(--metadata="ssh-keys=${SSH_USER}:${SSH_VPS_PUBKEY}")
fi

gce_ensure_instance "$VM" "$ZONE" \
  --machine-type="$VMTYPE" \
  --network="$NET" \
  --tags="$TAG" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --boot-disk-size="${DISK_GB}GB" \
  --boot-disk-type=pd-balanced \
  --address="$PUBLIC_IP" \
  "${META_ARGS[@]+"${META_ARGS[@]}"}"

if [[ "${SSH_VPS_SKIP_WAIT:-0}" != 1 ]]; then
  echo "waiting for ssh ${PUBLIC_IP}:22"
  i=0
  until timeout 3 bash -c "echo >/dev/tcp/${PUBLIC_IP}/22" 2>/dev/null; do
    i=$((i + 1))
    if (( i > 60 )); then
      echo "Error: SSH port never opened on ${PUBLIC_IP}" >&2
      echo "  ./ssh-vps.sh ${NAME}" >&2
      exit 1
    fi
    sleep 5
  done
fi

echo "user=${SSH_USER}"
echo "host=${PUBLIC_IP}"
echo "ssh=${SSH_USER}@${PUBLIC_IP}"
echo "no startup-script"
