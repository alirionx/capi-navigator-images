#!/bin/bash
# Boots a built image the way CAPMOX does (NoCloud seed ISO, QEMU guest agent channel) and checks
# that it is a working kubeadm node: cloud-init done via NoCloud, containerd and guest agent up,
# `kubeadm init` without preflight errors, node registered.
#
#   ./smoke-test.sh output/<os>-kube-<version>.qcow2
#
# Needs qemu-system-x86, qemu-utils, cloud-image-utils, socat, openssh-client; KVM if available.
set -euo pipefail
IMG="$(readlink -f "${1:?image}")"
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/smoke.XXXXXX")"
PORT="${SSH_PORT:-2222}"
QEMU_PID=""
cleanup() { [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

ssh-keygen -q -t ed25519 -N "" -f "$WORK/key"
cat > "$WORK/user-data" <<EOF
#cloud-config
hostname: smoke-test
users:
  - name: smoke
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys: ["$(cat "$WORK/key.pub")"]
EOF
cloud-localds "$WORK/seed.iso" "$WORK/user-data"
qemu-img create -q -f qcow2 -F qcow2 -b "$IMG" "$WORK/disk.qcow2" 20G

ACCEL=(-cpu max)
[ -w /dev/kvm ] && ACCEL=(-enable-kvm -cpu host)
qemu-system-x86_64 "${ACCEL[@]}" -smp 2 -m 3072 -display none \
  -drive file="$WORK/disk.qcow2",if=virtio -drive file="$WORK/seed.iso",media=cdrom \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:${PORT}-:22 -device virtio-net-pci,netdev=n0 \
  -chardev socket,path="$WORK/qga.sock",server=on,wait=off,id=qga0 \
  -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -serial file:"$WORK/console.log" &
QEMU_PID=$!

SSH=(ssh -q -i "$WORK/key" -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=5 smoke@127.0.0.1)
for i in $(seq 1 90); do "${SSH[@]}" true 2>/dev/null && break; sleep 5; done
if ! "${SSH[@]}" true 2>/dev/null; then
  echo "FAIL: no SSH after 450 s; console:" >&2; tail -40 "$WORK/console.log" >&2; exit 1
fi
echo "ssh up after ~$((i * 5)) s"

"${SSH[@]}" 'bash -s' <<'EOF'
set -euo pipefail
cloud-init status --wait >/dev/null || true
cloud-init status --long | sed -n '1,6p'
cloud-init status --long | grep -q 'DataSourceNoCloud' || { echo "FAIL: not NoCloud"; exit 1; }
[ "$(cloud-init status --format json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["errors"]))')" = 0 ] \
  || { echo "FAIL: cloud-init errors"; exit 1; }
cat /etc/capi-image-release
systemctl is-active containerd qemu-guest-agent
. /etc/capi-image-release
sudo kubeadm init --kubernetes-version "$KUBERNETES_VERSION" --pod-network-cidr 10.244.0.0/16 > /tmp/init.log 2>&1 \
  || { tail -30 /tmp/init.log; echo "FAIL: kubeadm init"; exit 1; }
grep -E 'WARNING' /tmp/init.log || echo "no kubeadm warnings"
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide
sudo crictl images
EOF

# The guest agent answers on its virtio channel (CAPMOX reads cloud-init status through it).
reply="$( (echo '{"execute":"guest-ping"}'; sleep 2) | socat -t 3 - UNIX-CONNECT:"$WORK/qga.sock")"
echo "guest agent: $reply"
[[ "$reply" == *'"return"'* ]] || { echo "FAIL: guest agent" >&2; exit 1; }
echo "PASS: $(basename "$IMG")"
