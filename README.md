# capi-navigator-images (spike)

> [!WARNING]
> **For testing purposes only.** These images and scripts are an experiment and are provided
> "as is", without any warranty or support. They are not maintained, receive no security updates
> and must not be used in production. The author accepts no responsibility or liability for any
> damage, data loss or other consequences of using them. Use at your own risk.

Cluster API node images for kubeadm, built from stock cloud images with `virt-customize`:
containerd and runc (release binaries, checksums), kubelet/kubeadm/kubectl/cri-tools/kubernetes-cni
from `pkgs.k8s.io` (exact version, only these held), QEMU guest agent, conntrack, socat; containerd
with `SystemdCgroup`, registry mirrors from `/etc/containerd/certs.d` and the pause image kubeadm
expects. Versions of the image are in `/etc/capi-image-release`.

A spike for air-gapped kubeadm clusters in [CAPI Navigator](https://github.com/alirionx/capi-navigator).
For anything beyond testing, build your own images, e.g. with the official
[Image Builder](https://image-builder.sigs.k8s.io/).

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
with `kubeadm init`. The images are workflow artifacts with a short retention; with **release**
switched on, the run also creates a GitHub release `images-<date>-<run>` with all images and a
`SHA256SUMS` (assets up to 2 GiB each; the images are 0.8–1.4 GB).

```bash
gh release download images-<date>-<run> -R alirionx/capi-navigator-images -p 'debian-13-*' -p SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

## Proxmox VE

```bash
qm create 9000 --name debian-13-kube-v1.36.5 --ostype l26 --cpu host --cores 2 --memory 4096 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --serial0 socket --vga serial0 --agent enabled=1
qm disk import 9000 debian-13-kube-v1.36.5.qcow2 local-zfs
qm set 9000 --virtio0 local-zfs:vm-9000-disk-0 --boot order=virtio0 --ide2 local-zfs:cloudinit
qm template 9000
```

## License

[Apache License 2.0](LICENSE). The images contain third-party software (Ubuntu or Debian, Kubernetes,
containerd, runc and others) under their own licenses.
