#!/bin/bash
# Builds a Cluster API node image for kubeadm from a stock cloud image with virt-customize.
#
#   ./build.sh <os> <kubernetes-version>      e.g. ./build.sh ubuntu-2604 v1.36.5
#
# <os>: ubuntu-2404 | ubuntu-2604 | debian-13 (amd64). Needs libguestfs-tools and qemu-utils;
# runs as root or with a readable kernel in /boot (libguestfs appliance). KVM speeds it up a lot.
# Output: output/<os>-kube-<version>.qcow2 plus .sha256
set -euo pipefail
cd "$(dirname "$0")"

OS="${1:?os: ubuntu-2404 | ubuntu-2604 | debian-13}"
K8S_VERSION="${2:?Kubernetes version, e.g. v1.36.5}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-2.4.2}"
RUNC_VERSION="${RUNC_VERSION:-1.5.2}"
export TMPDIR="${TMPDIR:-/var/tmp}"        # libguestfs appliance; /tmp is often a small tmpfs
[[ "$K8S_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version: $K8S_VERSION" >&2; exit 1; }

# Stock cloud images and their checksum lists.
case "$OS" in
  ubuntu-2404) BASE_URL=https://cloud-images.ubuntu.com/noble/current
               BASE=noble-server-cloudimg-amd64.img; SUMS=SHA256SUMS; SUMCMD=sha256sum ;;
  ubuntu-2604) BASE_URL=https://cloud-images.ubuntu.com/resolute/current
               BASE=resolute-server-cloudimg-amd64.img; SUMS=SHA256SUMS; SUMCMD=sha256sum ;;
  debian-13)   BASE_URL=https://cloud.debian.org/images/cloud/trixie/latest
               BASE=debian-13-genericcloud-amd64.qcow2; SUMS=SHA512SUMS; SUMCMD=sha512sum ;;
  *) echo "unsupported os: $OS" >&2; exit 1 ;;
esac

mkdir -p cache output
[ -f "cache/$BASE" ] || curl -fsSL -o "cache/$BASE" "$BASE_URL/$BASE"
curl -fsSL "$BASE_URL/$SUMS" | awk -v f="$BASE" '$2 == f || $2 == "*" f { print $1 "  cache/" f }' \
  | grep . | $SUMCMD -c

OUT="output/${OS}-kube-${K8S_VERSION}.qcow2"
cp "cache/$BASE" "$OUT"
qemu-img resize -q "$OUT" 8G

printf 'K8S_VERSION=%s\nCONTAINERD_VERSION=%s\nRUNC_VERSION=%s\nBASE_IMAGE=%s\n' \
  "$K8S_VERSION" "$CONTAINERD_VERSION" "$RUNC_VERSION" "$BASE" > output/capi-versions

# The root file system is partition 1 in the Ubuntu and Debian cloud images.
virt-customize -a "$OUT" \
  --run-command 'growpart /dev/sda 1 && resize2fs /dev/sda1' \
  --install qemu-guest-agent,conntrack,socat,ebtables,ethtool,curl,gnupg,ca-certificates \
  --upload output/capi-versions:/tmp/capi-versions \
  --upload prepare-node.sh:/tmp/prepare-node.sh \
  --run-command 'bash /tmp/prepare-node.sh && rm -f /tmp/prepare-node.sh /tmp/capi-versions' \
  --run-command 'apt-get clean && rm -rf /var/lib/apt/lists/*' \
  --run-command 'cloud-init clean --logs --seed' \
  --truncate /etc/machine-id
rm -f output/capi-versions

# Compress (the image is sparse anyway) and record the checksum.
qemu-img convert -O qcow2 -c "$OUT" "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
(cd output && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
qemu-img info "$OUT" | grep -E 'virtual size|disk size'
echo "Done: $OUT"
