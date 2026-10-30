# capi-navigator-images (spike)

Cluster API node images for kubeadm, built from stock cloud images with `virt-customize`:
containerd and runc (release binaries, checksums), kubelet/kubeadm/kubectl/cri-tools/kubernetes-cni
from `pkgs.k8s.io` (exact version, only these held), QEMU guest agent, conntrack, socat; containerd
with `SystemdCgroup`, registry mirrors from `/etc/containerd/certs.d` and the pause image kubeadm
expects. Versions of the image are in `/etc/capi-image-release`.

Spike for air-gapped kubeadm clusters in CAPI Navigator (backlog BL-01, BL-05); not published.

## Build locally

```bash
sudo apt-get install -y libguestfs-tools qemu-utils            # build
sudo apt-get install -y qemu-system-x86 cloud-image-utils socat  # smoke test
sudo ./build.sh debian-13 v1.36.5         # → output/debian-13-kube-v1.36.5.qcow2 (+ .sha256)
sudo ./smoke-test.sh output/debian-13-kube-v1.36.5.qcow2
```

Or with Docker only (same toolchain as in CI, Debian 13 with libguestfs 1.54):

```bash
./build-in-container.sh debian-13 v1.36.5
```

Operating systems: `ubuntu-2404`, `ubuntu-2604`, `debian-13` (amd64).

## GitHub Actions

**Actions → Build node images → Run workflow**: JSON lists of operating systems and Kubernetes
versions; every combination is built, booted with a NoCloud seed (as CAPMOX does) and initialised
with `kubeadm init`. The images are workflow artifacts with a short retention, no releases.

## Proxmox VE

```bash
qm create 9000 --name debian-13-kube-v1.36.5 --ostype l26 --cpu host --cores 2 --memory 4096 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --serial0 socket --vga serial0 --agent enabled=1
qm disk import 9000 debian-13-kube-v1.36.5.qcow2 local-zfs
qm set 9000 --virtio0 local-zfs:vm-9000-disk-0 --boot order=virtio0 --ide2 local-zfs:cloudinit
qm template 9000
```
