#!/bin/bash
# Runs build.sh in a Debian 13 container, so the build uses the same libguestfs everywhere
# (1.54 networks its appliance with QEMU user networking; Ubuntu 24.04's 1.52 needs passt, which
# AppArmor blocks on GitHub runners). Needs Docker; /dev/kvm is passed through when present.
#
#   ./build-in-container.sh <os> <kubernetes-version>
set -euo pipefail
cd "$(dirname "$0")"
KVM=()
[ -e /dev/kvm ] && KVM=(--device /dev/kvm)

docker run --rm "${KVM[@]}" -v "$PWD:/work" -w /work \
  -e CONTAINERD_VERSION -e RUNC_VERSION -e DEBUG_NET \
  debian:trixie bash -c '
    set -euo pipefail
    apt-get update -q >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
      libguestfs-tools linux-image-amd64 qemu-utils curl ca-certificates >/dev/null
    virt-customize --version
    ./build.sh "$@"
    chown -R '"$(id -u):$(id -g)"' output cache
  ' build "$@"
