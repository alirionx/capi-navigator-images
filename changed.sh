#!/bin/bash
# Tells whether a release of the given images would bring something new (IMG-F-34): yes if the build
# files changed since the newest release `images-*`, or if one of the images is in no release yet
# (e.g. a new Kubernetes patch in the rule). Prints the reason; exit code 0 = changed, 1 = nothing new.
#
#   ./changed.sh debian-13-qga debian-13-kube-v1.36.6 …
#
# Needs gh and the Git history with tags (fetch-depth 0 in CI).
set -euo pipefail
cd "$(dirname "$0")"
REPO="${GITHUB_REPOSITORY:-alirionx/capi-navigator-images}"
# The files that go into an image; the same list as the push paths of build.yml.
BUILD_FILES=(build.sh build-in-container.sh prepare-node.sh smoke-test.sh matrix.sh versions.env
             .github/workflows/build.yml)

tags="$(gh release list -R "$REPO" -L 1000 --json tagName,createdAt \
  --jq 'map(select(.tagName | startswith("images-"))) | sort_by(.createdAt) | reverse | .[].tagName')"
[ -n "$tags" ] || { echo "no release yet"; exit 0; }
latest="$(head -1 <<<"$tags")"

if ! git rev-parse -q --verify "refs/tags/$latest" >/dev/null; then
  echo "tag $latest not in the local history, assuming changes"; exit 0
fi
if ! git diff --quiet "$latest" HEAD -- "${BUILD_FILES[@]}"; then
  echo "build files changed since $latest:"; git diff --stat "$latest" HEAD -- "${BUILD_FILES[@]}"
  exit 0
fi

released="$(for tag in $tags; do
  gh release view "$tag" -R "$REPO" --json assets --jq '.assets[].name | select(endswith(".qcow2"))'
done)"
new=()
for image in "$@"; do grep -qxF "${image}.qcow2" <<<"$released" || new+=("$image"); done
if [ "${#new[@]}" -gt 0 ]; then echo "not released yet: ${new[*]}"; exit 0; fi

echo "nothing changed since $latest: same build files, every image released"
exit 1
