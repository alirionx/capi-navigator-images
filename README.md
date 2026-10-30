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

Besides, per operating system a **guest-agent-only image** (`<os>-qga`): the stock cloud image with
only the QEMU guest agent added, which CAPMOX needs on Proxmox VE (e.g. for RKE2 and k0s, or kubeadm
installed at first boot).

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
./build-in-container.sh debian-13 qga       # → output/debian-13-qga.qcow2
```

Operating systems: `ubuntu-2404`, `ubuntu-2604`, `debian-12`, `debian-13` (amd64).

## Which images exist

The rule in [`versions.env`](versions.env) decides what is built by default and kept in the releases:
the two newest Ubuntu LTS and Debian releases, each as `qga` image and with the two newest patch
releases of the two Kubernetes minors listed there (resolved from `dl.k8s.io`).
`./matrix.sh images` prints the current list.

## GitHub Actions

**Actions → Build node images → Run workflow**: without input the rule decides; JSON lists of
operating systems and Kubernetes versions replace it for one run. Every combination is built, booted
with a NoCloud seed (as CAPMOX does) and, for kubeadm images, initialised with `kubeadm init`. The
images are workflow artifacts with a short retention; with **release** switched on, the run also
creates a GitHub release `images-<date>-<run>` with all images and a `SHA256SUMS` (assets up to
2 GiB each; the kubeadm images are 0.8–1.4 GB).

After a release, **Clean up releases** keeps only the newest build of every image of the rule and
deletes older builds and images outside the rule (releases left empty are deleted). Started by hand
it is a dry run by default; locally: `./cleanup.sh` (dry run) or `DRY_RUN=false ./cleanup.sh`.

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
