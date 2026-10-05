#!/usr/bin/env bash
# Unit tests for gce/ssh-vps.sh (no live GCP).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_ok() {
  local msg="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "OK ${msg}"
  else
    echo "FAIL ${msg}"
    fail=1
  fi
}

assert_contains() {
  local msg="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "OK ${msg}"
  else
    echo "FAIL ${msg} (missing ${needle})"
    fail=1
  fi
}

assert_not_contains() {
  local msg="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "FAIL ${msg} (unexpected ${needle})"
    fail=1
  else
    echo "OK ${msg}"
  fi
}

write_fake_gcloud() {
  local dest="$1"
  cat > "$dest" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${GCLOUD_LOG}"
if [[ "$*" == *"config get-value project"* ]]; then
  echo test-proj
  exit 0
fi
case "$1 $2 $3" in
  "compute networks describe")
    [[ -f "${GCE_STATE}/net-$4" ]] && exit 0 || exit 1 ;;
  "compute networks create")
    touch "${GCE_STATE}/net-$4"; exit 0 ;;
  "compute addresses describe")
    name="$4"
    if [[ "$*" == *"--format=get(address)"* ]]; then
      [[ -f "${GCE_STATE}/addr-${name}" ]] || exit 1
      echo 203.0.113.10
      exit 0
    fi
    [[ -f "${GCE_STATE}/addr-${name}" ]] && exit 0 || exit 1 ;;
  "compute addresses create")
    touch "${GCE_STATE}/addr-$4"; exit 0 ;;
  "compute firewall-rules describe")
    [[ -f "${GCE_STATE}/fw-$4" ]] && exit 0 || exit 1 ;;
  "compute firewall-rules create")
    touch "${GCE_STATE}/fw-$4"; exit 0 ;;
  "compute instances describe")
    [[ -f "${GCE_STATE}/vm-$4" ]] && exit 0 || exit 1 ;;
  "compute instances create")
    touch "${GCE_STATE}/vm-$4"; exit 0 ;;
  "compute instances add-metadata")
    exit 0 ;;
  "compute instances reset")
    exit 0 ;;
  "compute instances delete")
    rm -f "${GCE_STATE}/vm-$4"; exit 0 ;;
  "compute firewall-rules delete")
    rm -f "${GCE_STATE}/fw-$4"; exit 0 ;;
  "compute addresses delete")
    rm -f "${GCE_STATE}/addr-$4"; exit 0 ;;
  "compute networks delete")
    rm -f "${GCE_STATE}/net-$4"; exit 0 ;;
esac
exit 0
EOF
  chmod 755 "$dest"
}

SSH_VPS="${ROOT}/ssh-vps.sh"

echo "== bash -n ssh-vps"
assert_ok "ssh-vps exists" test -x "$SSH_VPS"
assert_ok "bash -n ssh-vps.sh" bash -n "$SSH_VPS"

echo "== CLI"
help_out=$(bash "$SSH_VPS" --help 2>&1 || true)
assert_contains "help Usage" "$help_out" "Usage:"
assert_contains "help Examples" "$help_out" "Examples:"
assert_contains "help extra-ports" "$help_out" "--extra-ports"
assert_contains "help ssh-pubkey" "$help_out" "--ssh-pubkey"
src=$(cat "$SSH_VPS")
assert_contains "wraps via console/run.sh" "$src" "console/run.sh"
set +e
noargs=$(bash "$SSH_VPS" 2>&1)
no_rc=$?
set -e
[[ $no_rc -ne 0 ]] && echo "OK no args fails" || { echo "FAIL no args succeeded"; fail=1; }
assert_contains "no args example" "$noargs" "ssh-vps.sh"

echo "== dry-run"
dry=$(bash "$SSH_VPS" lab1 --dry-run 2>&1)
assert_contains "dry network" "$dry" "lab1-network"
assert_contains "dry ssh fw" "$dry" "tcp:22"
assert_contains "dry no startup note" "$dry" "no startup-script"
assert_not_contains "dry no clone" "$dry" "9ai-network"
assert_contains "dry ssh= user@host" "$dry" "ssh=debian@"
assert_not_contains "dry extra join port" "$dry" "tcp:9418"

dry2=$(bash "$SSH_VPS" lab1 --dry-run --extra-ports tcp:9418,udp:1194 2>&1)
assert_contains "dry extra tcp" "$dry2" "tcp:9418"
assert_contains "dry extra udp" "$dry2" "udp:1194"

dry4=$(bash "$SSH_VPS" lab1 --dry-run --ssh-pubkey /dev/null 2>&1)
assert_contains "dry ssh-keys" "$dry4" "ssh-keys"

echo "== fake gcloud create"
PATH_DIR="${tmpdir}/bin"
mkdir -p "$PATH_DIR" "${tmpdir}/state"
write_fake_gcloud "${PATH_DIR}/gcloud"
export GCLOUD_LOG="${tmpdir}/gcloud.log"
export GCE_STATE="${tmpdir}/state"
: > "$GCLOUD_LOG"
out=$(PATH="${PATH_DIR}:$PATH" SSH_VPS_SKIP_WAIT=1 bash "$SSH_VPS" vpnbox1 2>&1)
assert_contains "create ssh key" "$out" "ssh=debian@203.0.113.10"
assert_contains "create static_ip" "$out" "static_ip=203.0.113.10"
log=$(cat "$GCLOUD_LOG")
assert_contains "gcloud created instance" "$log" "instances create vpnbox1-vm"
assert_not_contains "no startup-script metadata" "$log" "startup-script"
assert_contains "fw ssh" "$log" "vpnbox1-fw-ssh"

: > "$GCLOUD_LOG"
out2=$(PATH="${PATH_DIR}:$PATH" SSH_VPS_SKIP_WAIT=1 bash "$SSH_VPS" vpnbox1 --extra-ports tcp:9418,udp:1194 2>&1)
log2=$(cat "$GCLOUD_LOG")
assert_contains "extra fw join" "$log2" "tcp:9418"
assert_contains "extra fw ovpn" "$log2" "udp:1194"

echo "== fake gcloud delete"
: > "$GCLOUD_LOG"
PATH="${PATH_DIR}:$PATH" bash "$SSH_VPS" vpnbox1 --delete >/dev/null
log3=$(cat "$GCLOUD_LOG")
assert_contains "delete instance" "$log3" "instances delete vpnbox1-vm"

exit "$fail"
