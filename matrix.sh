#!/bin/bash
# Resolves the images the rule in versions.env asks for (IMG-F-60): every operating system of
# OPERATING_SYSTEMS, each with the guest-agent-only image and a kubeadm image of the two newest patch
# releases of every minor in KUBERNETES_MINORS (from dl.k8s.io/release/stable-<minor>.txt).
#
#   ./matrix.sh os            # one operating system per line
#   ./matrix.sh kubernetes    # one Kubernetes version per line, e.g. v1.36.6
#   ./matrix.sh images        # one image name per line, e.g. debian-13-qga, debian-13-kube-v1.36.6
set -euo pipefail
cd "$(dirname "$0")"
. ./versions.env

kubernetes() {
  local minor latest patch
  for minor in $KUBERNETES_MINORS; do
    latest="$(curl -fsSL "https://dl.k8s.io/release/stable-${minor}.txt")"
    patch="${latest#"v${minor}."}"
    [[ "$patch" =~ ^[0-9]+$ ]] || { echo "unexpected stable-${minor}.txt: $latest" >&2; return 1; }
    echo "v${minor}.${patch}"
    if [ "$patch" -gt 0 ]; then echo "v${minor}.$((patch - 1))"; fi
  done
}

case "${1:?os | kubernetes | images}" in
  os) printf '%s\n' $OPERATING_SYSTEMS ;;
  kubernetes) kubernetes ;;
  images)
    versions="$(kubernetes)"
    for os in $OPERATING_SYSTEMS; do
      echo "${os}-qga"
      for v in $versions; do echo "${os}-kube-${v}"; done
    done ;;
  *) echo "unknown: $1" >&2; exit 1 ;;
esac
