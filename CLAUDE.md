# CLAUDE.md – capi-navigator-images

This file tells Claude Code how to work in this repository. Read it fully before every session.

## What this project is

Build scripts and a GitHub Actions workflow for **Cluster API node images for kubeadm**: a stock
Ubuntu or Debian cloud image, customized with `virt-customize`, that contains everything a kubeadm
node needs (containerd, runc, kubelet, kubeadm, kubectl, cri-tools, kubernetes-cni, QEMU guest
agent, conntrack, socat). Per operating system there is also a guest-agent-only image
(`<os>-qga`): the stock image plus the QEMU guest agent, for clusters that install Kubernetes
themselves (RKE2, k0s, online kubeadm) on Proxmox VE. Every image is booted and tested (kubeadm
images with `kubeadm init`) before it is released.

The images exist to test **air-gapped kubeadm clusters** in
[CAPI Navigator](https://github.com/alirionx/capi-navigator) (ADR-0032 there), mainly on Proxmox VE
with CAPMOX. They are **test images only**: no warranty, no support, no security updates. This
repository is not a supported image source; for anything real, users build their own images (e.g.
with the official Image Builder).

## Source of truth

- **Requirements:** `docs/requirements.md`. Always follow it. If this file and the requirements
  disagree, the requirements win; point out the conflict instead of guessing.
- **Context in CAPI Navigator** (separate repository, usually checked out at `~/capi-navigator`):
  `docs/adr/0032-kubeadm-on-capi-images.md`, FP-29 part B in `docs/requirements.md`
  (FP29-F-14, FP29-F-19, FP29-F-20) and `versions.yaml` (`kubeadm` catalog, `kubeadmRuntime`).
  Read them when a change touches the image contents or the versions. Never change that
  repository from here.

## Layout

| File | Purpose |
| --- | --- |
| `build.sh` | Downloads and verifies the stock cloud image, runs `virt-customize`, compresses, writes `.sha256`. Output in `output/`, downloads cached in `cache/` (both git-ignored). |
| `versions.env` | The containerd and runc pins and the image rule (operating systems, Kubernetes minors): the only place they are set, overridable by environment. |
| `matrix.sh` | Resolves the rule: operating systems, Kubernetes versions (two newest patches per minor from `dl.k8s.io`), image names. |
| `cleanup.sh` | Keeps the newest released build of every image of the rule, deletes the rest from the releases. Dry run by default. |
| `prepare-node.sh` | Runs inside the image during the build: kernel modules, sysctl, containerd and runc, Kubernetes packages, containerd configuration, `/etc/capi-image-release`. |
| `build-in-container.sh` | Runs `build.sh` in a `debian:trixie` container (libguestfs 1.54). Used by CI; the recommended local way. |
| `smoke-test.sh` | Boots an image like CAPMOX (NoCloud seed, guest agent channel) and runs `kubeadm init`. |
| `.github/workflows/build.yml` | Manual workflow: matrix from the rule (or input lists), build, smoke test, artifacts, optional release and cleanup. |
| `.github/workflows/cleanup.yml` | Runs `cleanup.sh`, after each release or by hand (dry run by default). |

## Commands

```bash
./build-in-container.sh debian-13 v1.36.5               # build with Docker (same toolchain as CI)
./build-in-container.sh debian-13 qga                   # guest-agent-only image
./matrix.sh images                                      # images the rule asks for today
./cleanup.sh                                            # dry run of the cleanup (needs gh)
sudo ./build.sh debian-13 v1.36.5                       # build on the host (libguestfs-tools, qemu-utils)
sudo ./smoke-test.sh output/debian-13-kube-v1.36.5.qcow2  # boot test (qemu-system-x86, cloud-image-utils, socat)
DEBUG_NET=1 ./build-in-container.sh …                   # print DNS and routes of the libguestfs appliance
CONTAINERD_VERSION=… RUNC_VERSION=… ./build-in-container.sh …   # override the runtime pins
gh workflow run build.yml                               # CI build of the rule (ask first)
gh workflow run build.yml -f os='["debian-13"]' -f kubernetes='["v1.36.5"]'   # one combination
```

A build with KVM takes about 90 s plus downloads; without KVM it is much slower.

## Hard rules

1. **Test images only.** The warning in `README.md` and in every release description stays. Never
   describe the images as supported, maintained or production-ready.
2. **Verify every download.** Base images against the distribution's checksum list, containerd and
   runc against their release checksums, Kubernetes packages through the signed `pkgs.k8s.io`
   repository. No `curl | bash`, no unverified binaries.
3. **Exact versions.** One Kubernetes version per image; the build fails if that version is not in
   `pkgs.k8s.io`. Only the Kubernetes packages are held, so OS packages can still be updated.
4. **`/etc/capi-image-release` is an interface.** CAPI Navigator's install script reads it
   (ADR-0032). Keys may be added, never renamed or removed; the format stays `KEY=value`.
5. **Works like CAPMOX expects.** NoCloud boot, QEMU guest agent enabled, `cloud-init clean`,
   truncated `/etc/machine-id`, nothing node-specific left in the image.
6. **containerd ready for air-gapped clusters.** `SystemdCgroup = true`,
   `config_path = '/etc/containerd/certs.d'` (clusters write their `hosts.toml` files there) and
   the pause image exactly as `kubeadm config images list` reports it. The build checks all three.
7. **Nothing secret in an image.** No credentials, registry settings, SSH keys or users are baked
   in; clusters bring them through cloud-init.
8. **One toolchain.** CI builds in the Debian 13 container; local builds should too. Do not go back
   to patching the Ubuntu runner (see CI notes).

## CI notes (learned the hard way)

- libguestfs 1.52 (Ubuntu 24.04) networks its appliance with passt, which AppArmor blocks on GitHub
  runners and which refuses to run as root. libguestfs 1.54 (Debian 13) uses QEMU user networking
  and works; hence the container build.
- `/dev/kvm` needs a udev rule on the runner to be usable by the runner user; it is passed into the
  container when present.
- libguestfs needs a readable kernel: the container installs `linux-image-amd64`.
- `TMPDIR` defaults to `/var/tmp` (the appliance is large, `/tmp` is often a small tmpfs); CI sets
  `TMPDIR=/tmp`, which has room on the runners.
- Release assets are limited to 2 GiB each; compressed images are 0.8–1.4 GB.

## Verify, don't guess

Base image URLs, package repository layouts, containerd's default configuration (field names change
between major versions) and kubeadm's API version change over time. Check the current upstream
documentation or the actual output (`containerd config default`, `kubeadm config images list`)
before changing them; never rely on remembered field names.

## Versions and the image rule

Follow `docs/requirements.md`, section 5. `versions.env` holds the rule: the two newest Ubuntu LTS
and Debian releases (by hand) and the Kubernetes minors (by hand, in line with CAPI Navigator's
kubeadm catalog); the two newest patches per minor are resolved automatically. containerd and runc
follow `kubeadmRuntime` in CAPI Navigator's `versions.yaml`. When you change a pin or the rule,
check it against that file and mention any difference to the user. A change of the rule also
changes what the cleanup deletes: run `./cleanup.sh` (dry run) and show the result first.

## Conventions

- Code, comments, commit messages and docs in **English**.
- Conventional commits with a scope where it helps: `feat:`, `fix(ci):`, `docs:`, `chore:`.
  Requirement IDs (e.g. `IMG-F-04`) go into commit messages where a change implements one.
- Bash with `set -euo pipefail`, short comments explaining *why*, the usage line at the top of each
  script. Keep the scripts small; no build framework (Packer, Ansible) without asking.
- Keep `README.md` current when commands, operating systems or versions change.

## Safety while working

- Ask before running the workflow, creating or deleting releases or tags, running the cleanup
  without dry run, or pushing. Releases are public (the repository is public).
- Ask before touching a real Proxmox VE, registry or cluster.
- Local builds need root or Docker and download several GB; say so before starting one.

## Definition of done

- [ ] The changed image builds (`./build-in-container.sh`) and passes `./smoke-test.sh`, locally
      or in the workflow, for every operating system the change affects.
- [ ] `bash -n` passes for every script (and `shellcheck` if available).
- [ ] No hard rule above is violated; `/etc/capi-image-release` stays compatible.
- [ ] `README.md` and `docs/requirements.md` (ticked acceptance criteria, status) are updated.
