# Requirements – capi-navigator-images

Status: 2026-10-30 · Requirement IDs: `IMG-F-xx` (functional), `IMG-NF-xx` (non-functional).
MUST, SHOULD and MAY as in RFC 2119.

## 1. Purpose and scope

This repository builds node images from stock cloud images for
[CAPI Navigator](https://github.com/alirionx/capi-navigator), mainly on Proxmox VE with CAPMOX:

- **Cluster API images for kubeadm** (`<os>-kube-<version>`), so that CAPI Navigator can run
  **air-gapped kubeadm clusters**: a node without internet access cannot install packages at first
  boot, so everything must be in the image (CAPI Navigator ADR-0032, FP29-F-19, FP29-F-20).
- **Guest-agent-only images** (`<os>-qga`): the stock image plus the QEMU guest agent, which CAPMOX
  needs to read the cloud-init status. They serve air-gapped RKE2 and k0s clusters on Proxmox VE
  (FP29-F-15) and online kubeadm clusters on stock images (ADR-0014).

**Goals**

- A small, readable recipe (`virt-customize` on a stock image) that users can copy and adapt.
- Images that are tested end to end (boot like CAPMOX, `kubeadm init`) before they are released.
- Test images for the development and acceptance tests of CAPI Navigator, following a fixed rule
  for which images exist (section 5).

**Non-goals**

- Supported or production images. The project publishes no supported images (ADR-0032); the
  official way for real use is Image Builder (`image-builder.sigs.k8s.io`), for OpenStack osism's
  images (`github.com/osism/k8s-capi-images`).
- Security updates or a release cadence for published images.
- RKE2 or k0s binaries in images (CAPI Navigator brings them as OCI artifacts).

## 2. Relation to CAPI Navigator

- CAPI Navigator's kubeadm install script is image-aware (ADR-0032). It compares
  `kubeadm version` with the target version: with kubeadm of the target version present it
  installs nothing and leaves containerd alone; with another version it changes only kubelet,
  kubeadm and kubectl; without kubeadm (stock or `qga` image) it installs everything. Air-gapped it
  only checks that `kubeadm version` equals the cluster's version.
- Air-gapped clusters write one `hosts.toml` per upstream registry into
  `/etc/containerd/certs.d` (FP29-F-14); the image's containerd must read that directory.
- The interface between both repositories is the image contents of section 3 and the file
  `/etc/capi-image-release` (section 4). There is no build-time dependency.

## 3. Functional requirements

### Build

- **IMG-F-01** MUST build an image per operating system and variant:
  `./build.sh <os> <version>` → `output/<os>-kube-<version>.qcow2`,
  `./build.sh <os> qga` → `output/<os>-qga.qcow2`, each plus `.sha256`.
- **IMG-F-02** MUST support the operating systems `ubuntu-2404`, `ubuntu-2604`, `debian-12` and
  `debian-13`, amd64, from the official cloud images (`cloud-images.ubuntu.com`,
  `cloud.debian.org`).
- **IMG-F-03** MUST verify the base image against the distribution's checksum list and cache it in
  `cache/`.
- **IMG-F-04** MUST install, in kubeadm images, containerd and runc from their release binaries,
  each verified with its release checksum, with containerd as systemd service.
- **IMG-F-05** MUST install, in kubeadm images, kubelet, kubeadm and kubectl of exactly the requested
  version plus cri-tools and kubernetes-cni from the signed `pkgs.k8s.io` repository of that minor
  version, hold only these packages, and fail if the version does not exist.
- **IMG-F-06** MUST install, in kubeadm images, the QEMU guest agent, conntrack, socat, ebtables and
  ethtool and enable containerd, kubelet and the guest agent.
- **IMG-F-07** MUST configure, in kubeadm images, what kubeadm expects: kernel modules `overlay` and
  `br_netfilter`, bridge netfilter and IP forwarding sysctls, `/etc/crictl.yaml` for containerd.
- **IMG-F-08** MUST configure, in kubeadm images, containerd with `SystemdCgroup = true`,
  `config_path = '/etc/containerd/certs.d'` and the pause image that `kubeadm config images list`
  reports for the version, and fail the build if any of the three is missing.
- **IMG-F-09** MUST leave every image generic: `cloud-init clean --logs --seed`, truncated
  `/etc/machine-id`, apt lists removed, no users, keys, credentials or registry settings.
- **IMG-F-10** MUST grow the root file system so that the image has 8 GiB virtual size, and write a
  compressed qcow2.
- **IMG-F-11** MUST build the same way locally and in CI through `build-in-container.sh`
  (`debian:trixie`, libguestfs 1.54), with KVM when `/dev/kvm` exists.
- **IMG-F-12** SHOULD allow overriding containerd and runc versions through `CONTAINERD_VERSION` and
  `RUNC_VERSION`, and print the appliance's network setup with `DEBUG_NET=1`.
- **IMG-F-13** MUST build the `qga` variant from the stock image with only the QEMU guest agent
  added (no Kubernetes packages, no containerd), plus `/etc/capi-image-release`.

### Smoke test

- **IMG-F-20** MUST boot an image like CAPMOX does: copy-on-write overlay, NoCloud seed ISO,
  virtio-serial channel `org.qemu.guest_agent.0`.
- **IMG-F-21** MUST check, for kubeadm images, that cloud-init used `DataSourceNoCloud` and reported
  no errors, that containerd and the guest agent are active, that `kubeadm init` with the image's
  version succeeds and the node is registered, and that the guest agent answers `guest-ping`.
- **IMG-F-22** SHOULD list kubeadm warnings and the pulled images in its output.
- **IMG-F-23** MUST check, for `qga` images, NoCloud without cloud-init errors, an active guest agent
  that answers `guest-ping`, and that no kubeadm is installed.

### GitHub Actions: build and release

- **IMG-F-30** MUST offer a manually triggered workflow that builds every combination of operating
  systems and variants in parallel (`fail-fast: false`). Without input lists the rule of section 5
  decides; optional JSON lists of operating systems and Kubernetes versions replace it for one run;
  a switch (default on) adds the `qga` variant.
- **IMG-F-31** MUST run the smoke test for every image (switch, default on).
- **IMG-F-32** MUST upload each image with its checksum as workflow artifact with configurable
  retention (default 3 days).
- **IMG-F-33** MAY create a GitHub release `images-<date>-<run>` with all images and one
  `SHA256SUMS`, only when every build succeeded; the description carries the warning of IMG-NF-01,
  the image sizes, the operating systems and variants, the runtime versions and the run that built
  it.

## 4. Interface: `/etc/capi-image-release`

- **IMG-F-40** MUST write `/etc/capi-image-release` as `KEY=value` lines:

  | Key | kubeadm | qga | Content |
  | --- | --- | --- | --- |
  | `IMAGE_VARIANT` | ✓ | ✓ | `kubeadm` or `qga` (added 2026-10-30; missing means `kubeadm`) |
  | `KUBERNETES_VERSION` | ✓ | – | e.g. `v1.36.5` |
  | `CONTAINERD_VERSION` | ✓ | – | e.g. `2.4.2` |
  | `RUNC_VERSION` | ✓ | – | e.g. `1.5.2` |
  | `PAUSE_IMAGE` | ✓ | – | as reported by `kubeadm config images list`, e.g. `registry.k8s.io/pause:<tag>` |
  | `BASE_IMAGE` | ✓ | ✓ | file name of the stock cloud image |
  | `BUILT` | ✓ | ✓ | UTC timestamp of the build (ISO 8601) |

- **IMG-F-41** MUST keep the file compatible: keys may be added, never renamed, removed or changed
  in meaning. A breaking change needs a coordinated change in CAPI Navigator first.

## 5. The image rule and versions

All of it is set in `versions.env`, the only place for versions and the rule (IMG-F-52);
`matrix.sh` resolves it.

- **IMG-F-60** MUST define the images that are built by default and kept as:
  - operating systems: the two newest Ubuntu LTS releases and the two newest Debian releases,
    maintained by hand in `OPERATING_SYSTEMS` (each needs its cloud image in `build.sh`);
    today `ubuntu-2604`, `ubuntu-2404`, `debian-13`, `debian-12`;
  - Kubernetes: the two newest patch releases of each minor in `KUBERNETES_MINORS`, resolved at run
    time from `dl.k8s.io/release/stable-<minor>.txt` (newest patch and the one before); today the
    minors `1.36` and `1.35`, giving v1.36.6, v1.36.5, v1.35.10, v1.35.9;
  - per operating system one `qga` image and one kubeadm image per Kubernetes version
    (today 4 × 5 = 20 images).
- **IMG-F-50** MUST keep `KUBERNETES_MINORS` in line with the kubeadm catalog of CAPI Navigator's
  `versions.yaml` (an image of a version the app does not offer cannot be used air-gapped,
  FP29-F-19). Patch releases newer than the catalog are intended: they are ready when the catalog
  moves on.
- **IMG-F-51** SHOULD use the containerd and runc versions of `kubeadmRuntime` in `versions.yaml`
  as defaults. A difference is allowed (the image-aware script keeps the image's containerd) but is
  mentioned in the change.
- **IMG-F-52** MUST keep each version pin and the rule in one place in this repository:
  `versions.env`, read by `build.sh`, `matrix.sh` and the release step of the workflow.
- The minors and the runtime versions are synchronised by hand when CAPI Navigator's catalog
  changes; there is no build-time dependency on the other repository.

### Cleanup

- **IMG-F-70** MUST offer a cleanup (`cleanup.sh`, workflow "Clean up releases") that keeps, of
  every image of the rule, only the newest released build, and deletes older builds and every image
  outside the rule from the releases `images-*`.
- **IMG-F-71** MUST rewrite `SHA256SUMS` and the image table of a release it changes and note there
  what it removed; a release without images left is deleted with its tag.
- **IMG-F-72** MUST run after every release of the build workflow (switch, default on), and MUST be
  a dry run by default when started by hand.
- **IMG-F-73** MUST stop without deleting anything when the rule cannot be resolved (e.g.
  `dl.k8s.io` unreachable).

## 6. Non-functional requirements

- **IMG-NF-00** The repository and its releases are public (decided 2026-10-30), as test images
  with the warning of IMG-NF-01; this does not make them supported images of CAPI Navigator.
- **IMG-NF-01** MUST state in `README.md` and every release that the images are for testing only,
  provided "as is", without warranty, support or security updates, and not for production.
- **IMG-NF-02** MUST verify every downloaded artifact (base image, binaries, packages); no
  unverified downloads, no `curl | bash`.
- **IMG-NF-03** MUST be reproducible in the sense of pinned inputs: the same OS, Kubernetes,
  containerd and runc versions give an image with the same software versions (the base image is the
  distribution's current one at build time and recorded in `BASE_IMAGE`).
- **IMG-NF-04** SHOULD build one image in under 5 minutes with KVM (about 90 s plus downloads
  today); a workflow job MUST finish within 45 minutes.
- **IMG-NF-05** MUST keep compressed images below 2 GiB (release asset limit).
- **IMG-NF-06** SHOULD stay small and readable: plain Bash scripts, no build framework.
- **IMG-NF-07** The repository is licensed under Apache License 2.0; the images contain third-party
  software under its own licenses, which `README.md` states.

## 7. Acceptance criteria

- [x] `ubuntu-2604` and `debian-13` with v1.35.9 and v1.36.5 build and pass the smoke test in GitHub
      Actions (2026-10-30).
- [x] `kubeadm init` runs without preflight errors on the images; cloud-init uses NoCloud and
      reports no errors; the guest agent answers.
- [x] A release with all images and `SHA256SUMS` was created by the workflow
      (`images-20261030-12`).
- [x] An air-gapped kubeadm cluster (Debian 13, v1.36.5, from `images-20261030-12`) came up on
      Proxmox VE 9.2 with CAPMOX v0.9.1 from an internal registry alone (CAPI Navigator ADR-0032,
      2026-10-30).
- [x] Each version pin and the rule live in one place (IMG-F-52).
- [x] `matrix.sh` resolves the rule to 20 images (2026-10-30); a dry run of the cleanup against the
      existing releases keeps everything that matches the rule.
- [x] The full rule (4 operating systems × `qga` + 4 Kubernetes versions) builds and passes the smoke
      test in GitHub Actions, including `ubuntu-2404`, `debian-12` and the `qga` images (run
      41125563800, 2026-10-30; 18.6 GB in all, kubeadm images 0.76–1.35 GB, `qga` 0.39–0.95 GB).
- [ ] A release of the full rule is created, and the cleanup after it removes the older builds of
      the same images and leaves releases without images deleted.
- [ ] `KUBERNETES_MINORS` and the runtime versions match CAPI Navigator's `versions.yaml`
      (IMG-F-50, IMG-F-51).

## 8. Outlook and open questions

- **Scheduled rebuilds**: a schedule (e.g. weekly) that builds and releases the rule, so new patch
  releases and OS updates arrive without a manual run.
- **Version sync**: a check in CI that compares `KUBERNETES_MINORS` and the runtime pins with CAPI
  Navigator's `versions.yaml`.
- **Further operating systems and architectures**, e.g. RHEL-compatible images (rpm repository of
  `pkgs.k8s.io`, `kernel-modules-extra`) or arm64.
- **Air-gapped test in CI**: smoke test without a default route, with a local registry mirror
  through `hosts.toml`.
