#!/bin/bash
# Runs inside the image (virt-customize): turns a stock Ubuntu or Debian cloud image into a Cluster
# API node image for kubeadm. Versions come from /tmp/capi-versions (written by build.sh).
set -euo pipefail
. /tmp/capi-versions                       # K8S_VERSION, CONTAINERD_VERSION, RUNC_VERSION
K8S_MINOR="${K8S_VERSION%.*}"              # v1.36
ARCH=amd64
export DEBIAN_FRONTEND=noninteractive

# Kernel modules and sysctl, as kubeadm expects them.
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/kubernetes.conf
printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n' \
  > /etc/sysctl.d/99-kubernetes.conf

# containerd and runc: official release binaries, verified with their checksums.
tmp="$(mktemp -d)"; cd "$tmp"
ctr="containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz"
curl -fsSLO "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/${ctr}"
curl -fsSLO "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/${ctr}.sha256sum"
sha256sum -c "${ctr}.sha256sum"
tar -C /usr/local -xzf "${ctr}"
curl -fsSLO "https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH}"
curl -fsSLO "https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.sha256sum"
grep " runc.${ARCH}\$" runc.sha256sum | sha256sum -c
install -m 0755 "runc.${ARCH}" /usr/local/sbin/runc
cd /; rm -rf "$tmp"
cat > /etc/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
After=network.target local-fs.target dbus.service

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

# kubelet, kubeadm, kubectl, cri-tools, kubernetes-cni of exactly this version; only they are held.
PKGS="https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb"
mkdir -p /etc/apt/keyrings
curl -fsSL "${PKGS}/Release.key" | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] ${PKGS}/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -q
deb="$(apt-cache madison kubeadm | awk -v v="${K8S_VERSION#v}-" 'index($3, v) == 1 && !f { print $3; f = 1 }')"
[ -n "$deb" ] || { echo "kubeadm ${K8S_VERSION} not found in ${PKGS}" >&2; exit 1; }
apt-get install -y -q "kubelet=$deb" "kubeadm=$deb" "kubectl=$deb" cri-tools kubernetes-cni
apt-mark hold kubelet kubeadm kubectl cri-tools kubernetes-cni

# containerd configuration: systemd cgroups, registry mirrors from /etc/containerd/certs.d
# (air-gapped clusters write hosts.toml files there), pause image exactly as kubeadm wants it.
# The build appliance has no valid host name, which kubeadm validates as node name: pass one.
cat > /tmp/kubeadm-images.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  name: image-build
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: ${K8S_VERSION}
EOF
pause="$(kubeadm config images list --config /tmp/kubeadm-images.yaml | grep '/pause:')"
rm -f /tmp/kubeadm-images.yaml
mkdir -p /etc/containerd/certs.d
/usr/local/bin/containerd config default \
  | sed -e 's/SystemdCgroup = false/SystemdCgroup = true/' \
        -e "s#^\( *\)config_path = .*#\1config_path = '/etc/containerd/certs.d'#" \
        -e "s#^\( *\)sandbox = .*#\1sandbox = '${pause}'#" > /etc/containerd/config.toml
grep -q "SystemdCgroup = true" /etc/containerd/config.toml
grep -q "config_path = '/etc/containerd/certs.d'" /etc/containerd/config.toml
grep -q "sandbox = '${pause}'" /etc/containerd/config.toml
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\n' > /etc/crictl.yaml

systemctl enable containerd.service kubelet.service

cat > /etc/capi-image-release <<EOF
KUBERNETES_VERSION=${K8S_VERSION}
CONTAINERD_VERSION=${CONTAINERD_VERSION}
RUNC_VERSION=${RUNC_VERSION}
PAUSE_IMAGE=${pause}
BASE_IMAGE=${BASE_IMAGE}
BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

